import 'package:flutter_shadcn_cli/src/application/services/theme/theme_models.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_preset_prompt.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_registry_source.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_service.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/installer.dart';

/// Installer entry points for the v2 theme flow.
///
/// The implementation lives in
/// `lib/src/application/services/theme/theme_service.dart`; this extension is
/// the `Installer`-shaped door for `init` (which picks a preset while it
/// installs the always-on core), for `add`/`update`, and for anyone who prefers
/// the installer over building a [ThemeService] by hand.
///
/// The single call the other flows need is [applyThemePreset]. It reuses the
/// installer's manifest and install root, so `app_theme.dart` always lands next
/// to the installed `theme/` layer.
///
/// Registry source: pass [source] when the caller already has a reader (B4's
/// `RegistryFileReader`, a local cache); otherwise the registry is resolved
/// from `.shadcn/config.json`, honouring the `--registry` overrides.
extension InstallerThemePart on Installer {
  /// Builds a [ThemeService] bound to this installer's project, manifest and
  /// install root.
  Future<ThemeService> themeService({
    ThemeRegistrySource? source,
    String? namespace,
    String? registryPath,
    String? registryUrl,
    bool offline = false,
  }) async {
    if (source != null) {
      return ThemeService(
        projectRoot: projectRoot,
        source: source,
        manifest: manifest,
        config: await ShadcnConfig.load(projectRoot),
        installRootOverride: installRoot,
        logger: logger,
      );
    }
    return ThemeService.resolve(
      projectRoot: projectRoot,
      installRoot: installRoot,
      namespace: namespace,
      registryPathOverride: registryPath,
      registryUrlOverride: registryUrl,
      offline: offline,
      logger: logger,
    );
  }

  /// The one call `init` / `add` / `update` need: apply [presetId] to
  /// `<installRoot>/theme/app_theme.dart`.
  ///
  /// Returns `null` (after a warning) when the project has no registry
  /// configured, so `init` can continue and let `theme apply` finish the job
  /// later. Anything else (unknown preset, invalid preset JSON, unreadable or
  /// invalid manifest) raises [ThemeApplyException].
  Future<ThemeApplyResult?> applyThemePreset(
    String presetId, {
    bool refresh = false,
    ThemeRegistrySource? source,
    String? namespace,
    String? registryPath,
    String? registryUrl,
    bool offline = false,
  }) async {
    if (presetId.trim().isEmpty) return null;
    final ThemeService service;
    try {
      service = await themeService(
        source: source,
        namespace: namespace,
        registryPath: registryPath,
        registryUrl: registryUrl,
        offline: offline,
      );
    } on ThemeApplyException catch (error) {
      if (error.message.startsWith(_noRegistryPrefix)) {
        logger.warnToStderr('${error.message} Skipping theme "$presetId".');
        return null;
      }
      rethrow;
    }
    return service.apply(presetId, refresh: refresh);
  }

  /// Every preset in the manifest `themes` map, sorted by id.
  Future<List<ThemeCatalogEntry>> listThemePresets({
    ThemeRegistrySource? source,
    String? namespace,
    String? registryPath,
    String? registryUrl,
    bool offline = false,
  }) async {
    final service = await themeService(
      source: source,
      namespace: namespace,
      registryPath: registryPath,
      registryUrl: registryUrl,
      offline: offline,
    );
    return service.listPresets();
  }

  /// Interactive preset choice; `null` when the user skips or types something
  /// that is not a preset.
  Future<ThemeCatalogEntry?> promptThemePreset({
    ThemeRegistrySource? source,
    String? namespace,
    String? registryPath,
    String? registryUrl,
    bool offline = false,
  }) async {
    final presets = await listThemePresets(
      source: source,
      namespace: namespace,
      registryPath: registryPath,
      registryUrl: registryUrl,
      offline: offline,
    );
    logger.info('Select a theme preset (press Enter to skip):');
    return promptForThemePreset(
      presets,
      question: 'Theme number: ',
      write: logger.info,
    );
  }

  /// Start of the "no registry configured" message, used to degrade to a
  /// warning inside [applyThemePreset].
  static const String _noRegistryPrefix = 'No shadcn registry is configured';
}
