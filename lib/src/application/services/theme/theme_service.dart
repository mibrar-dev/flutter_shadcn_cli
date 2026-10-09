import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/app_theme_generator.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/app_theme_values.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_models.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_preset_validator.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_registry_source.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/resolver/v1/project_path_guard.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/theme_preset.dart';
import 'package:path/path.dart' as p;

/// The theme flow for registry manifest v2: preset list and preset apply.
///
/// One `ThemeService` owns a project root, a registry source (which yields the
/// v2 manifest and the preset JSONs) and the project's `shadcn.lock`. The
/// only file it writes is `<installRoot>/theme/app_theme.dart`, and because
/// that file is user-owned it is only rewritten when the bytes on disk still
/// match the lock or the caller passes `refresh: true`.
///
/// B4 (`init`, `add`) and B5 (`theme`, `update`) call [apply] / [listPresets];
/// nothing else in the CLI needs to know how a preset becomes Dart.
class ThemeService {
  ThemeService({
    required this.projectRoot,
    required this.source,
    required this.manifest,
    this.config,
    this.installRootOverride,
    CliLogger? logger,
  })  : _logger = logger ?? CliLogger(),
        _lock = ShadcnLockRepository(projectRoot);

  /// Project root (the directory holding `.shadcn/` and `shadcn.lock`).
  final String projectRoot;

  /// Registry the manifest and presets come from.
  final ThemeRegistrySource source;

  /// The validated v2 manifest.
  final RegistryManifest manifest;

  /// Project config, when the caller has it; only used for `installPath`.
  final ShadcnConfig? config;

  /// Install root chosen by the caller (B4's `Installer` resolves one for the
  /// whole install). It wins over [config] and the manifest default so
  /// `app_theme.dart` always lands next to the installed `theme/` layer.
  final String? installRootOverride;

  final CliLogger _logger;
  final ShadcnLockRepository _lock;

  /// `theme` layer directory of the install root.
  static const String themeLayerDir = 'theme';

  /// File name of the generated, values-only theme.
  static const String appThemeFileName = 'app_theme.dart';

  /// Builds a service from `.shadcn/config.json`: resolves the registry,
  /// loads and validates the manifest. Throws [ThemeApplyException] when no
  /// registry is configured or the manifest is invalid.
  static Future<ThemeService> resolve({
    required String projectRoot,
    String? installRoot,
    String? namespace,
    String? registryPathOverride,
    String? registryUrlOverride,
    bool offline = false,
    CliLogger? logger,
  }) async {
    final config = await ShadcnConfig.load(projectRoot);
    final source = ThemeRegistrySourceResolver.requireFromConfig(
      config,
      namespace: namespace,
      registryPathOverride: registryPathOverride,
      registryUrlOverride: registryUrlOverride,
      offline: offline,
    );
    return ThemeService(
      projectRoot: projectRoot,
      source: source,
      manifest: await source.loadManifest(),
      config: config,
      installRootOverride: installRoot,
      logger: logger,
    );
  }

  /// Project-relative install root: the caller's override wins, then the
  /// project's `installPath`, then the manifest default.
  String get installRoot {
    final override = installRootOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return normalizeLockPath(override);
    }
    final configured = config?.installPath?.trim();
    if (configured != null && configured.isNotEmpty) {
      return normalizeLockPath(configured);
    }
    final fromManifest = manifest.install.root.trim();
    return normalizeLockPath(
      fromManifest.isEmpty ? 'lib/ui/shadcn' : fromManifest,
    );
  }

  /// Project-relative path of the generated theme file.
  String get appThemeRelativePath =>
      normalizeLockPath(p.join(installRoot, themeLayerDir, appThemeFileName));

  /// Absolute path of the generated theme file.
  File get appThemeFile => File(p.join(projectRoot, appThemeRelativePath));

  /// Every preset in the manifest, sorted by id, with the locked one marked.
  Future<List<ThemeCatalogEntry>> listPresets() async {
    final currentId = (await _lock.load()).theme?.id;
    final entries = manifest.themes.values
        .map((preset) =>
            ThemeCatalogEntry.fromPreset(preset, currentId: currentId))
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return entries;
  }

  /// Renders `themes/<presetId>.json` into `<installRoot>/theme/app_theme.dart`.
  ///
  /// [refresh] forces the rewrite when the file on disk drifted. Without it a
  /// drifted file is left alone and the drift is reported.
  Future<ThemeApplyResult> apply(String presetId,
      {bool refresh = false}) async {
    final preset = findPreset(presetId);
    if (preset == null) {
      throw ThemeApplyException(
        'Unknown theme preset "$presetId".',
        details: <String>[
          'Available presets: '
              '${(await listPresets()).map((e) => e.id).join(', ')}',
        ],
      );
    }
    final decoded = await source.readJson(preset.file);
    final validation =
        ThemePresetValidator.validate(decoded, label: preset.file);
    if (!validation.isValid) {
      throw ThemeApplyException(
        'Theme preset ${preset.file} is invalid (themes.schema.json v2).',
        details: validation.errors,
      );
    }
    if (decoded['id'] != preset.id) {
      throw ThemeApplyException(
        'Theme preset ${preset.file} declares id "${decoded['id']}" but the '
        'manifest lists it as "${preset.id}".',
      );
    }

    final AppThemeValues values;
    try {
      values = AppThemeValues.fromJson(decoded);
    } on FormatException catch (error) {
      throw ThemeApplyException('${preset.file}: ${error.message}');
    }
    final rendered = renderAppTheme(values);
    final renderedSha = FileHashing.ofText(rendered);

    final target = appThemeFile;
    final relativePath = appThemeRelativePath;
    final lock = await _lock.load();
    // The recorded digest describes the bytes at this path, whoever wrote
    // them: comparing it with the file on disk is what tells "CLI-owned, safe
    // to regenerate" from "the user edited it".
    final recorded = lock.theme;
    final recordedSha = recorded != null &&
            recorded.path == relativePath &&
            recorded.sha256.isNotEmpty
        ? recorded.sha256
        : null;

    final status = await _writeTarget(
      target: target,
      relativePath: relativePath,
      rendered: rendered,
      renderedSha: renderedSha,
      recordedSha: recordedSha,
      refresh: refresh,
    );
    if (status.status != ThemeApplyStatus.drift) {
      // The lock must describe the bytes that exist: a refusal leaves the
      // previous selection in place.
      await _recordSelection(lock, preset, relativePath, renderedSha);
    }
    await _persistConfigThemeId(preset.id,
        onlyIfApplied: status.status != ThemeApplyStatus.drift);

    final result = ThemeApplyResult(
      status: status.status,
      presetId: preset.id,
      presetName: preset.name.isEmpty ? preset.id : preset.name,
      path: relativePath,
      sha256: renderedSha,
      sourceFile: preset.file,
      drift: status.drift,
    );
    _report(result);
    return result;
  }

  /// Finds a preset by id, then by display name (both case insensitive).
  ThemePreset? findPreset(String identifier) {
    final needle = identifier.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final preset in manifest.themes.values) {
      if (preset.id.toLowerCase() == needle) return preset;
    }
    for (final preset in manifest.themes.values) {
      if (preset.name.toLowerCase() == needle) return preset;
    }
    return null;
  }

  Future<_WriteOutcome> _writeTarget({
    required File target,
    required String relativePath,
    required String rendered,
    required String renderedSha,
    required String? recordedSha,
    required bool refresh,
  }) async {
    if (!await target.exists()) {
      await _write(target, relativePath, rendered);
      return const _WriteOutcome(ThemeApplyStatus.created);
    }
    final diskSha = await FileHashing.ofFile(target);
    if (diskSha == renderedSha) {
      return const _WriteOutcome(ThemeApplyStatus.unchanged);
    }
    // The lock's digest matches the bytes on disk, so the file is exactly what
    // the CLI wrote: switching presets may rewrite it without --refresh.
    if (recordedSha != null && recordedSha == diskSha) {
      await _write(target, relativePath, rendered);
      return const _WriteOutcome(ThemeApplyStatus.refreshed);
    }
    final drift = ThemeDrift(
      kind: recordedSha == null
          ? ThemeDriftKind.untracked
          : ThemeDriftKind.modified,
      path: relativePath,
      recordedSha256: recordedSha,
      actualSha256: diskSha,
    );
    if (!refresh) {
      return _WriteOutcome(ThemeApplyStatus.drift, drift: drift);
    }
    await _write(target, relativePath, rendered);
    return _WriteOutcome(ThemeApplyStatus.refreshed, drift: drift);
  }

  Future<void> _write(File target, String relativePath, String rendered) async {
    final safePath = ProjectPathGuard.resolveSafeWritePath(
      projectRoot: projectRoot,
      destinationRelativePath: relativePath,
    );
    final file = File(safePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(rendered, flush: true);
    _logger.detail('  ↳ wrote $relativePath');
  }

  Future<void> _recordSelection(
    ShadcnLock lock,
    ThemePreset preset,
    String relativePath,
    String sha256,
  ) async {
    final existing = lock.theme;
    final alreadyRecorded = existing != null &&
        existing.id == preset.id &&
        existing.path == relativePath &&
        existing.sha256 == sha256 &&
        lock.installRoot.isNotEmpty;
    if (alreadyRecorded) return;
    await _lock.save(
      lock
          .withTheme(
            LockThemeSelection(
              id: preset.id,
              path: relativePath,
              sha256: sha256,
            ),
          )
          .copyWith(
            installRoot: lock.installRoot.isEmpty ? installRoot : null,
          ),
    );
  }

  /// Mirrors the preset id into `.shadcn/config.json` for the installer's
  /// own bookkeeping. Only touches an existing config file, and never records
  /// a preset that was not applied.
  Future<void> _persistConfigThemeId(
    String presetId, {
    required bool onlyIfApplied,
  }) async {
    if (!onlyIfApplied) return;
    if (!await ShadcnConfig.configFile(projectRoot).exists()) return;
    final current = await ShadcnConfig.load(projectRoot);
    if (current.themeId == presetId) return;
    await ShadcnConfig.save(
      projectRoot,
      current.copyWith(themeId: presetId),
    );
  }

  void _report(ThemeApplyResult result) {
    final path = result.path;
    switch (result.status) {
      case ThemeApplyStatus.created:
        _logger.success('Applied theme ${result.presetName} ($path)');
      case ThemeApplyStatus.refreshed:
        _logger.success('Applied theme ${result.presetName} ($path)');
      case ThemeApplyStatus.unchanged:
        _logger.info(
          'Theme ${result.presetName} already applied ($path); nothing to do.',
        );
      case ThemeApplyStatus.drift:
        final drift = result.drift;
        final reason = drift?.kind == ThemeDriftKind.untracked
            ? 'the file exists but shadcn.lock has no theme entry for it'
            : 'it was modified locally';
        _logger.warnToStderr(
          'Refusing to overwrite ${drift?.path ?? path}: $reason '
          '(recorded ${drift?.recordedSha256 ?? '(none)'}, '
          'on disk ${drift?.actualSha256 ?? '(none)'}).',
        );
        _logger.warnToStderr(
          'Re-run with --refresh to regenerate it from ${result.sourceFile}.',
        );
    }
    _logger.detail('  ↳ sha256 ${result.sha256}');
  }
}

class _WriteOutcome {
  const _WriteOutcome(this.status, {this.drift});

  final ThemeApplyStatus status;
  final ThemeDrift? drift;
}
