import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer_file_install_part.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/pub_package_resolver.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/application/services/manifest_closure.dart';
import 'package:flutter_shadcn_cli/src/application/services/update/update_lock_builder.dart';
import 'package:flutter_shadcn_cli/src/application/services/update/update_report.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:path/path.dart' as p;

export 'package:flutter_shadcn_cli/src/application/services/update/update_report.dart';

/// Hash-driven `update`: overwrite unchanged registry files with the manifest's
/// current content, install files the manifest has added since the install,
/// report locally modified files, and never touch user-owned `<name>_theme.dart`
/// files (plan §2.3).
class UpdateService {
  const UpdateService({
    required this.manifest,
    required this.reader,
    required this.projectRoot,
    required this.installRoot,
    this.manifestSha256 = '',
    this.themeRegenerator,
    this.pubRunner,
    this.logger,
    this.runPubGet = true,
  });

  final RegistryManifest manifest;
  final RegistryFileReader reader;

  /// Absolute project root.
  final String projectRoot;

  /// Project-relative install root recorded by the lock (or the manifest).
  final String installRoot;

  final String manifestSha256;

  /// Re-renders `theme/app_theme.dart` for a preset id. Injected by the command
  /// (B6's theme service) so this service stays independent of the theme flow.
  final Future<void> Function(String presetId)? themeRegenerator;

  /// Runs `flutter pub`; when null, package drift is not checked or applied.
  final PubCommandRunner? pubRunner;

  final CliLogger? logger;

  /// Whether an applied update runs `pub get` after a pubspec change.
  final bool runPubGet;

  ShadcnLockRepository get _lockRepo => ShadcnLockRepository(projectRoot);

  Future<UpdateReport> run({
    Set<String>? componentIds,
    bool check = false,
  }) async {
    final lock = await _lockRepo.load();
    final root = lock.installRoot.isEmpty ? installRoot : lock.installRoot;
    final themePath = lock.theme?.path;
    final files = InstallerFileInstaller(
      projectRoot: projectRoot,
      installRoot: root,
      reader: reader,
    );

    final added = <String>[];
    final updated = <String>[];
    final modified = <String>[];
    final removedUpstream = <String>[];
    final missing = <String>[];
    final unchanged = <String>[];
    final newHashes = <String, String>{};
    final newLayerFiles = <LockLayer, Map<String, String>>{};
    final newComponentFiles = <String, Map<String, String>>{};
    final newUserOwned = <String, Map<String, String>>{};

    // Pass 1: files the lock already tracks.
    final tracked = _trackedRegistryFiles(lock, componentIds);
    for (final entry in tracked.entries) {
      final target = entry.key;
      if (themePath != null && target == themePath) {
        continue;
      }
      final source = _sourceFor(target, root);
      if (source == null) {
        continue;
      }
      if (!manifest.declaredFiles.contains(source)) {
        removedUpstream.add(target);
        continue;
      }
      final bytes = await reader.readBytes(source);
      if (bytes == null) {
        removedUpstream.add(target);
        continue;
      }
      final newSha = FileHashing.ofBytes(bytes);
      final disk = File(p.join(projectRoot, target));
      final diskSha = await FileHashing.ofFileIfExists(disk);
      if (diskSha == null) {
        missing.add(target);
        newHashes[target] = newSha;
        if (!check) {
          await _write(disk, bytes);
        }
      } else if (FileHashing.matches(entry.value, diskSha)) {
        if (diskSha == newSha) {
          unchanged.add(target);
        } else {
          updated.add(target);
          newHashes[target] = newSha;
          if (!check) {
            await _write(disk, bytes);
          }
        }
      } else {
        modified.add(target);
      }
    }

    // Pass 2: files the manifest added to the installed closure.
    final closure = ManifestClosureResolver(manifest).resolve(
      _targetComponentIds(lock, componentIds),
      includeCore: false,
    );
    final known = tracked.keys.toSet();
    for (final source in closure.files) {
      if (!manifest.declaredFiles.contains(source)) {
        continue;
      }
      final target = files.targetPathFor(source);
      if (known.contains(target) ||
          (themePath != null && target == themePath)) {
        continue;
      }
      final bytes = await reader.readBytes(source);
      if (bytes == null) {
        continue;
      }
      final newSha = FileHashing.ofBytes(bytes);
      final disk = File(p.join(projectRoot, target));
      final diskSha = await FileHashing.ofFileIfExists(disk);
      if (diskSha == null) {
        added.add(target);
        _recordNewFile(
            source, target, newSha, newLayerFiles, newComponentFiles);
        if (!check) {
          await _write(disk, bytes);
        }
      } else if (FileHashing.matches(newSha, diskSha)) {
        unchanged.add(target);
        _recordNewFile(
            source, target, newSha, newLayerFiles, newComponentFiles);
      } else {
        // An untracked local file at a registry path: never clobber it.
        modified.add(target);
      }
    }

    // Pass 3: user-owned files the manifest added (install only if absent).
    for (final id in closure.components) {
      final component = manifest.components[id];
      if (component == null) {
        continue;
      }
      for (final source in component.userOwned) {
        final target = files.targetPathFor(source);
        if (known.contains(target)) {
          continue;
        }
        final bytes = await reader.readBytes(source);
        if (bytes == null) {
          continue;
        }
        final disk = File(p.join(projectRoot, target));
        if (!await disk.exists()) {
          added.add(target);
          if (!check) {
            await _write(disk, bytes);
          }
        }
        newUserOwned.putIfAbsent(id, () => {})[target] =
            FileHashing.ofBytes(bytes);
      }
    }

    // Pass 4: pub packages the closure needs.
    var packagesAdded = <String>[];
    final runner = pubRunner;
    if (runner != null) {
      final resolver = PubPackageResolver(
        projectRoot: projectRoot,
        runner: runner,
        logger: logger,
      );
      final plan = await resolver.plan(
        closure.packages.map(PubPackageRequirement.fromPackageRef),
      );
      if (check) {
        packagesAdded = plan.missing.map((package) => package.name).toList();
      } else {
        final applied = await resolver.apply(plan, runPubGet: runPubGet);
        packagesAdded = applied.missing.map((package) => package.name).toList();
      }
    }

    var themeRegenerated = false;
    if (!check) {
      await _lockRepo.save(
        UpdateLockBuilder(manifest: manifest, manifestSha256: manifestSha256)
            .build(
          lock,
          newHashes: newHashes,
          newLayerFiles: newLayerFiles,
          newComponentFiles: newComponentFiles,
          newUserOwned: newUserOwned,
          closure: closure,
        ),
      );
      themeRegenerated = await _regenerateTheme(lock);
    }

    return UpdateReport(
      added: _sorted(added),
      updated: _sorted(updated),
      modified: _sorted(modified),
      removedUpstream: _sorted(removedUpstream),
      missing: _sorted(missing),
      unchanged: _sorted(unchanged),
      packagesAdded: packagesAdded..sort(),
      themeRegenerated: themeRegenerated,
      applied: !check,
    );
  }

  /// Re-renders `<installRoot>/theme/app_theme.dart` from the locked preset.
  ///
  /// B6 owns the theme service; `update` only asks it to refresh. Returns
  /// false when there is no locked theme (nothing to do).
  Future<bool> _regenerateTheme(ShadcnLock lock) async {
    final themeId = lock.theme?.id;
    final regenerate = themeRegenerator;
    if (themeId == null || themeId.isEmpty || regenerate == null) {
      return false;
    }
    await regenerate(themeId);
    return true;
  }

  /// Installed component ids that still exist in the manifest.
  List<String> _targetComponentIds(ShadcnLock lock, Set<String>? componentIds) {
    final ids = componentIds ?? lock.componentIds.toSet();
    return [
      for (final id in ids)
        if (manifest.components.containsKey(id)) id,
    ]..sort();
  }

  Map<String, String> _trackedRegistryFiles(
    ShadcnLock lock,
    Set<String>? componentIds,
  ) {
    final result = <String, String>{};
    for (final layer in LockLayer.values) {
      result.addAll(lock.layerState(layer).files);
    }
    for (final component in lock.components) {
      if (componentIds != null && !componentIds.contains(component.id)) {
        continue;
      }
      result.addAll(component.files);
    }
    return result;
  }

  /// Maps a project-relative target back to its registry-relative source.
  String? _sourceFor(String target, String root) {
    final normalizedTarget = normalizeLockPath(target);
    final prefix = root.isEmpty ? '' : '${normalizeLockPath(root)}/';
    if (prefix.isNotEmpty && normalizedTarget.startsWith(prefix)) {
      return normalizedTarget.substring(prefix.length);
    }
    return null;
  }

  /// Records a newly installed registry file against its layer or component.
  void _recordNewFile(
    String source,
    String target,
    String sha256,
    Map<LockLayer, Map<String, String>> layerFiles,
    Map<String, Map<String, String>> componentFiles,
  ) {
    final segments = source.split('/');
    final head = segments.first;
    final layer = LockLayer.fromKey(head);
    if (layer != null) {
      layerFiles.putIfAbsent(layer, () => {})[target] = sha256;
      return;
    }
    if (head == InstallerFileInstaller.componentsDir && segments.length > 1) {
      componentFiles.putIfAbsent(segments[1], () => {})[target] = sha256;
    }
  }

  Future<void> _write(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  static List<String> _sorted(Iterable<String> values) =>
      values.toSet().toList()..sort();
}
