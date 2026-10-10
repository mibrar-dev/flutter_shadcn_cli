import 'package:flutter_shadcn_cli/src/application/services/installer/installer.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_manifest_loader.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_source.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_source_resolver.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_registry_source.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_service.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';

/// Everything a registry-backed command needs: the project config, the
/// registry source, the validated v2 manifest, the installer and the theme
/// service, all sharing one install root (plan §2).
class CommandContext {
  const CommandContext({
    required this.projectRoot,
    required this.config,
    required this.source,
    required this.loadedManifest,
    required this.installer,
    required this.themeService,
    required this.logger,
  });

  /// Absolute project root (holds `.shadcn/` and `shadcn.lock`).
  final String projectRoot;

  final ShadcnConfig config;
  final RegistrySource source;
  final LoadedRegistryManifest loadedManifest;
  final Installer installer;
  final ThemeService themeService;
  final CliLogger logger;

  /// Project-relative install root every command uses.
  String get installRoot => installer.installRoot;
}

/// Builds a [CommandContext] from the raw CLI inputs.
///
/// Resolution is centralised so `init`/`add`/`remove`/`update`/`doctor` and the
/// read-only commands all agree on the registry, the manifest digest and the
/// install root.
class CommandContextResolver {
  const CommandContextResolver._();

  static Future<CommandContext> resolve({
    required String projectRoot,
    required CliLogger logger,
    String? registryOverride,
    String? installRootOverride,
    bool offline = false,
    RegistryHttpClient? httpClient,
  }) async {
    final config = await ShadcnConfig.load(projectRoot);
    final source = RegistrySourceResolver.resolve(
      projectRoot: projectRoot,
      config: config,
      registryOverride: registryOverride,
      offline: offline,
      httpClient: httpClient,
    );
    final loaded = await RegistryManifestLoader(source).load();
    final installRoot = _installRoot(config, loaded, installRootOverride);

    final installer = Installer(
      manifest: loaded.manifest,
      projectRoot: projectRoot,
      reader: RegistrySourceFileReader(source),
      installRoot: installRoot,
      manifestSha256: loaded.sha256,
      logger: logger,
    );

    final themeService = ThemeService(
      projectRoot: projectRoot,
      source: ThemeRegistrySource.overReader(
        source.readString,
        registryRoot: source.localRoot,
        describe: source.describe,
      ),
      manifest: loaded.manifest,
      config: config,
      installRootOverride: installRoot,
      logger: logger,
    );

    return CommandContext(
      projectRoot: projectRoot,
      config: config,
      source: source,
      loadedManifest: loaded,
      installer: installer,
      themeService: themeService,
      logger: logger,
    );
  }

  /// The caller's `--dir`, then `.shadcn/config.json` `installPath`, then the
  /// manifest default (`lib/ui/shadcn`).
  static String _installRoot(
    ShadcnConfig config,
    LoadedRegistryManifest loaded,
    String? override,
  ) {
    final explicit = override?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit.replaceAll('\\', '/');
    }
    final configured = config.installPath?.trim();
    if (configured != null && configured.isNotEmpty) {
      return configured.replaceAll('\\', '/');
    }
    final fromManifest = loaded.manifest.install.root.trim();
    return fromManifest.isEmpty ? 'lib/ui/shadcn' : fromManifest;
  }
}
