import 'package:flutter_shadcn_cli/src/application/services/installer/dry_run_plan.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_file_install_part.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_lock_part.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_remove_part.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/pub_package_resolver.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_plan_part.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/application/services/manifest_closure.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';

/// Two installed components would define the same public symbol.
///
/// The v2 replacement for the v1 namespace-collision policy (plan §2.2).
class SingleOwnerViolationException implements Exception {
  const SingleOwnerViolationException(this.violations);

  /// symbol -> the components that would define it.
  final Map<String, List<String>> violations;

  @override
  String toString() {
    final details = violations.entries
        .map((entry) => '${entry.key} (${entry.value.join(', ')})')
        .join('; ');
    return 'Single-owner preflight failed: $details would be defined more than '
        'once. Remove the conflicting component or choose a different one.';
  }
}

/// The v2 installer core: closure resolution, verbatim file copy, single-owner
/// preflight, pubspec deltas and the lockfileVersion 2 record.
///
/// It is deliberately independent of the CLI presentation layer: commands
/// (batch B5) build a plan, print it for `--dry-run`/`--json`, then apply it.
class Installer {
  Installer({
    required this.manifest,
    required this.projectRoot,
    required RegistryFileReader reader,
    String? installRoot,
    CliLogger? logger,
    PubCommandRunner? pubRunner,
    this.manifestSha256 = '',
  })  : installRoot = installRoot ?? manifest.install.root,
        _reader = reader,
        logger = logger ?? CliLogger(),
        _pubRunner = pubRunner ?? const ProcessPubCommandRunner();

  final RegistryManifest manifest;

  /// Absolute project root.
  final String projectRoot;

  /// Project-relative install root, e.g. `lib/ui/shadcn`.
  final String installRoot;

  /// sha256 of `manifests/registry.json`, recorded in the lock.
  final String manifestSha256;

  final RegistryFileReader _reader;
  final CliLogger logger;
  final PubCommandRunner _pubRunner;

  InstallerFileInstaller get _files => InstallerFileInstaller(
        projectRoot: projectRoot,
        installRoot: installRoot,
        reader: _reader,
      );

  PubPackageResolver get _pubResolver => PubPackageResolver(
        projectRoot: projectRoot,
        runner: _pubRunner,
        logger: logger,
      );

  InstallerFilePlanner get _planner => InstallerFilePlanner(
        projectRoot: projectRoot,
        reader: _reader,
        installerFiles: _files,
      );

  ShadcnLockRepository get _lockRepo => ShadcnLockRepository(projectRoot);

  ManifestClosureResolver get _closureResolver =>
      ManifestClosureResolver(manifest);

  /// Transitive closure of [componentIds] plus [blockIds]; throws
  /// [ManifestClosureException] for an unknown id.
  ManifestClosure resolveClosure(
    Iterable<String> componentIds, {
    Iterable<String> blockIds = const [],
    bool includeCore = true,
  }) =>
      _closureResolver.resolve(
        componentIds,
        blockIds: blockIds,
        includeCore: includeCore,
      );

  /// Computes the plan without writing anything.
  Future<DryRunPlan> plan(
    Iterable<String> componentIds, {
    Iterable<String> blockIds = const [],
    bool includePreview = false,
    bool overwrite = false,
    bool includeCore = true,
  }) async {
    final requested = componentIds.toList();
    final requestedBlocks = blockIds.toList();
    final closure = resolveClosure(
      requested,
      blockIds: requestedBlocks,
      includeCore: includeCore,
    );
    await _preflightSingleOwner(closure);
    final files = await _planFiles(
      closure,
      includePreview: includePreview,
      overwrite: overwrite,
    );
    final packagePlan = await _pubResolver.plan(
      closure.packages.map(PubPackageRequirement.fromPackageRef),
    );
    return DryRunPlan(
      requested: requested,
      requestedBlocks: requestedBlocks,
      components: closure.components,
      blocks: closure.blocks,
      foundation: closure.foundation,
      theme: closure.theme,
      primitives: closure.primitives,
      files: files,
      packages: [
        for (final package in packagePlan.missing)
          PlannedPackage(
            name: package.name,
            sdk: package.sdk,
            constraint: package.constraint,
          ),
      ],
      includePreview: includePreview,
    );
  }

  /// Installs [componentIds] and [blockIds] (closure + core), or returns the
  /// plan when [dryRun] is true.
  Future<InstallReport> add(
    Iterable<String> componentIds, {
    Iterable<String> blockIds = const [],
    bool dryRun = false,
    bool includePreview = false,
    bool overwrite = false,
    bool includeCore = true,
    bool runPubGet = true,
  }) async {
    final plan = await this.plan(
      componentIds,
      blockIds: blockIds,
      includePreview: includePreview,
      overwrite: overwrite,
      includeCore: includeCore,
    );
    if (dryRun) {
      return InstallReport(plan: plan, applied: false);
    }

    final toWrite = [
      for (final file in plan.files)
        if (file.action == PlanAction.add || file.action == PlanAction.update)
          file,
    ];
    final written = <String>[];
    if (toWrite.isNotEmpty) {
      final sources = await _files.readAll(
        toWrite.map((file) => file.source),
      );
      _files.assertImportGuard({
        for (final entry in sources.entries)
          entry.key: decodeRegistryText(entry.value),
      });
      for (final file in toWrite) {
        await _files.write(
          source: file.source,
          target: file.target,
          bytes: sources[file.source]!,
        );
        written.add(file.target);
      }
    }

    final current = await _lockRepo.load();
    final delta = InstallLockBuilder(
      manifest: manifest,
      installRoot: installRoot,
      manifestSha256: manifestSha256,
    ).build(plan, current: current);
    await _lockRepo.save(current.mergeWith(delta));

    final packagePlan = await _pubResolver.plan(
      resolveClosure(
        componentIds,
        blockIds: blockIds,
        includeCore: includeCore,
      ).packages.map(PubPackageRequirement.fromPackageRef),
    );
    final applied = await _pubResolver.apply(packagePlan, runPubGet: runPubGet);

    return InstallReport(
      plan: plan,
      applied: true,
      written: written,
      packagesAdded: applied.missing.map((package) => package.name).toList(),
    );
  }

  /// Installs every component in the manifest (`add --all`).
  ///
  /// The v2 installer copies the whole closure at once, so the v1
  /// level-ordered bulk install (de35dd2 `_topologicalLevels`) is unnecessary:
  /// file copy order is irrelevant (plan §9.7).
  ///
  /// Blocks are a separate opt-in (`add <block>` or `add --all --blocks`):
  /// a block is a finished screen, so `--all` never installs 16 of them into
  /// an app by accident.
  Future<InstallReport> installAll({
    bool dryRun = false,
    bool includePreview = false,
    bool runPubGet = true,
    bool includeBlocks = false,
  }) =>
      add(
        manifest.components.keys,
        blockIds: includeBlocks ? manifest.blocks.keys : const [],
        dryRun: dryRun,
        includePreview: includePreview,
        runPubGet: runPubGet,
      );

  /// Installs the always-on layer core (all foundation + theme units) with no
  /// component; the `init` step (plan §2.1).
  Future<InstallReport> installCore({
    bool dryRun = false,
    bool runPubGet = true,
  }) =>
      add(
        const [],
        dryRun: dryRun,
        runPubGet: runPubGet,
        includeCore: true,
      );

  /// Removes [componentIds] and any layer unit no remaining install needs.
  Future<RemoveReport> remove(
    Iterable<String> componentIds, {
    bool force = false,
    bool purgeUserThemes = false,
    bool dryRun = false,
  }) {
    return InstallerRemover(
      manifest: manifest,
      projectRoot: projectRoot,
      logger: logger,
    ).remove(
      componentIds,
      force: force,
      purgeUserThemes: purgeUserThemes,
      dryRun: dryRun,
    );
  }

  Future<List<PlannedFile>> _planFiles(
    ManifestClosure closure, {
    required bool includePreview,
    required bool overwrite,
  }) =>
      _planner.plan(
        closure,
        includePreview: includePreview,
        overwrite: overwrite,
        userOwnedByComponent: {
          for (final id in closure.components)
            id: manifest.components[id]!.userOwned,
        },
      );

  Future<void> _preflightSingleOwner(ManifestClosure closure) async {
    final requested = closure.components.toSet();
    final owners = <String, String>{};
    final violations = <String, List<String>>{};

    void claim(String symbol, String owner) {
      final existing = owners[symbol];
      if (existing == null) {
        owners[symbol] = owner;
        return;
      }
      if (existing != owner) {
        final entries = violations.putIfAbsent(symbol, () => [existing]);
        if (!entries.contains(owner)) {
          entries.add(owner);
        }
      }
    }

    for (final id in closure.components) {
      for (final symbol in manifestSymbols(manifest.components[id]!.api)) {
        claim(symbol, id);
      }
    }
    final lock = await _lockRepo.load();
    for (final component in lock.components) {
      if (requested.contains(component.id)) {
        continue;
      }
      for (final symbol in component.api.symbols) {
        claim(symbol, component.id);
      }
    }
    if (violations.isNotEmpty) {
      throw SingleOwnerViolationException(violations);
    }
  }
}
