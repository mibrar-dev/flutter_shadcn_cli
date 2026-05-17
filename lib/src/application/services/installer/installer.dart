import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/component_manifest_resolver.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/dry_run_plan.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/init_config_overrides.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/install_target_policy.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_config_resolver.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_file_selection_policy.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_file_writer_service.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_manifest_service.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_alias_entry.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_dependency_update_result.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_registry_file_owner.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_shared_service.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/namespace_collision_policy.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/application/services/pubspec/pubspec_change_planner.dart';
import 'package:flutter_shadcn_cli/src/application/services/pubspec/pubspec_editor.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_dependency_graph.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/resolver/v1/project_path_guard.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/resolver/v1/resolver_v1_exception.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry/theme_index_entry.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry/theme_index_loader.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry/theme_preset_loader.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/state.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

part 'installer_theme_part.dart';
part 'installer_config_part.dart';
part 'installer_remove_part.dart';
part 'installer_dry_run_part.dart';
part 'installer_shared_part.dart';
part 'installer_manifest_part.dart';
part 'installer_file_install_part.dart';
part 'installer_platform_alias_part.dart';
part 'installer_pubspec_part.dart';
part 'installer_locale_part.dart';

class Installer {
  static const int _fileCopyConcurrency = 4;
  final Registry registry;
  final String targetDir;
  final CliLogger logger;
  final String? installPathOverride;
  final String? sharedPathOverride;
  final String? stateNamespace;
  final String? registryNamespace;
  final String? registryBaseUrlOverride;
  final String? themesPathOverride;
  final String? themesSchemaPathOverride;
  final Set<String>? includeFileKindsOverride;
  final Set<String>? excludeFileKindsOverride;
  final bool enableSharedGroups;
  final bool enableComposites;
  Set<String>? _installedComponentCache;
  final Set<String> _installingComponentIds = {};
  bool _initFilesEnsured = false;
  bool _deferAliases = false;
  bool _deferDependencyUpdates = false;
  final Map<String, dynamic> _pendingDependencies = {};
  final Set<String> _pendingAssets = {};
  final List<FontEntry> _pendingFonts = [];
  final Map<String, Future<void>> _componentInstallTasks = {};
  bool _deferComponentManifest = false;
  Future<void> _lockfileWriteQueue = Future<void>.value();
  ShadcnConfig? _cachedConfig;
  late final ComponentManifestResolver _manifestResolver;
  final InstallerConfigResolver _configResolver;
  final InstallerFileSelectionPolicy _fileSelectionPolicy;
  final InstallerManifestService _manifestService;
  final InstallerFileWriterService _fileWriter;
  final InstallerSharedService _sharedService;
  final InstallTargetPolicy _installTargetPolicy;

  Installer({
    required this.registry,
    required this.targetDir,
    CliLogger? logger,
    this.installPathOverride,
    this.sharedPathOverride,
    this.stateNamespace,
    this.registryNamespace,
    this.registryBaseUrlOverride,
    this.themesPathOverride,
    this.themesSchemaPathOverride,
    this.includeFileKindsOverride,
    this.excludeFileKindsOverride,
    this.enableSharedGroups = true,
    this.enableComposites = true,
    InstallerConfigResolver? configResolver,
    InstallerFileSelectionPolicy? fileSelectionPolicy,
    InstallerManifestService? manifestService,
    InstallerFileWriterService? fileWriter,
    InstallTargetPolicy? installTargetPolicy,
  })  : logger = logger ?? CliLogger(),
        _configResolver = configResolver ??
            InstallerConfigResolver(
              registry: registry,
              installPathOverride: installPathOverride,
              sharedPathOverride: sharedPathOverride,
              registryNamespace: registryNamespace,
            ),
        _fileSelectionPolicy = fileSelectionPolicy ??
            InstallerFileSelectionPolicy(
              includeFileKindsOverride: includeFileKindsOverride,
              excludeFileKindsOverride: excludeFileKindsOverride,
              registryNamespace: registryNamespace,
            ),
        _manifestService = manifestService ??
            InstallerManifestService(
              targetDir: targetDir,
              registry: registry,
              registryNamespace: registryNamespace,
              registryBaseUrlOverride: registryBaseUrlOverride,
            ),
        _fileWriter = fileWriter ??
            InstallerFileWriterService(
              registry: registry,
              logger: logger ?? CliLogger(),
            ),
        _sharedService = InstallerSharedService(
          registry: registry,
          logger: logger ?? CliLogger(),
        ),
        _installTargetPolicy =
            installTargetPolicy ?? const InstallTargetPolicy() {
    _manifestResolver = ComponentManifestResolver(
      registry: registry,
      logger: this.logger,
    );
  }

  Future<void> init({
    bool skipPrompts = false,
    InitConfigOverrides? configOverrides,
    String? themePreset,
  }) async {
    logger.header('Initializing flutter_shadcn');
    final autoReuseExistingSetup = await _shouldAutoReuseExistingSetup(
      skipPrompts: skipPrompts,
      configOverrides: configOverrides,
    );
    final hasMissingConfigValues =
        autoReuseExistingSetup ? await _hasMissingInitConfigValues() : false;
    final effectiveSkipPrompts =
        skipPrompts || (autoReuseExistingSetup && !hasMissingConfigValues);
    if (autoReuseExistingSetup) {
      logger.info(
        'Detected existing .shadcn config/state. Re-initializing with saved settings.',
      );
      if (hasMissingConfigValues) {
        logger.info(
          'Some saved init settings are missing. Re-opening prompts to complete setup.',
        );
      }
    }

    if (configOverrides != null && configOverrides.hasAny) {
      await _ensureConfigOverrides(configOverrides);
    } else if (effectiveSkipPrompts) {
      await _ensureConfigDefaults();
    } else {
      await _ensureConfig();
    }

    final config = await ShadcnConfig.load(targetDir);
    await _ensureAnalysisOptionsExclude(config);
    if (!effectiveSkipPrompts) {
      _printInitSummary(config, themePreset);
      final proceed = _confirmInitProceed();
      if (!proceed) {
        logger.warn('Initialization cancelled.');
        return;
      }
    }

    final coreShared = _coreSharedIdsForInit();
    await RegistryDependencyGraph(registry).validateSharedInstall(coreShared);
    final sharedToInstall = (await _resolveSharedDependencyClosure(
      coreShared.toSet(),
    ))
      ..removeWhere((id) => id.isEmpty);
    final sharedList = sharedToInstall.toList()..sort();

    logger.section('Installing core shared modules');
    var totalFiles = 0;
    for (final sharedId in sharedList) {
      final shared = registry.getSharedItem(sharedId);
      if (shared == null) {
        throw Exception('Shared module $sharedId not found');
      }
      logger.detail('  • $sharedId (${shared.files.length} files)');
      totalFiles += shared.files.length;
    }
    logger.detail('  Total: $totalFiles files');
    print('');

    for (final sharedId in sharedList) {
      await installShared(sharedId);
    }
    await _updateDependencies({'data_widget': '^0.0.2', 'gap': '^3.0.1'});
    if (themePreset != null && themePreset.isNotEmpty) {
      await applyThemeById(themePreset);
    } else if (!effectiveSkipPrompts) {
      await _promptThemeSelection();
    } else if (config.themeId != null && config.themeId!.isNotEmpty) {
      await applyThemeById(config.themeId!);
    } else if (autoReuseExistingSetup) {
      await _promptThemeSelection();
    }
    await generateAliases();
    await _updateComponentManifest();
    await _updateState();

    logger.success('Initialization complete');
    logger.detail('Aliases written to lib/ui/shadcn/app_components.dart');
  }

  Future<bool> _shouldAutoReuseExistingSetup({
    required bool skipPrompts,
    required InitConfigOverrides? configOverrides,
  }) async {
    if (skipPrompts || (configOverrides?.hasAny ?? false)) {
      return false;
    }
    final configExists = await ShadcnConfig.configFile(targetDir).exists();
    final stateExists = await ShadcnState.stateFile(targetDir).exists();
    return configExists && stateExists;
  }

  Future<bool> _hasMissingInitConfigValues() async {
    final config = await ShadcnConfig.load(targetDir);
    return config.installPath == null ||
        config.sharedPath == null ||
        config.includeReadme == null ||
        config.includeMeta == null ||
        config.includePreview == null;
  }

  Future<void> addComponent(
    String name, {
    bool installDependencies = true,
    Set<String>? ancestry,
  }) async {
    final component = await _manifestResolver.resolve(name);
    if (component == null) {
      logger.warn('Component "$name" not found');
      return;
    }

    if (installDependencies && ancestry == null) {
      await RegistryDependencyGraph(
        registry,
      ).validateComponentInstall([component.id]);
    }

    await ensureInitFiles(allowPrompts: false);
    await _ensureConfigLoaded();

    final stack = ancestry ?? <String>{};
    if (stack.contains(component.id)) {
      throw RegistryDependencyCycleException([...stack, component.id]);
    }
    stack.add(component.id);

    final existingTask = _componentInstallTasks[component.id];
    if (existingTask != null) {
      await existingTask;
      return;
    }

    final completer = Completer<void>();
    _componentInstallTasks[component.id] = completer.future;
    completer.future.ignore();

    if (_installingComponentIds.contains(component.id)) {
      logger.detail('Skipping ${component.id} (already installing)');
      _componentInstallTasks.remove(component.id);
      completer.complete();
      return;
    }

    try {
      final installed = await _installedComponentIds();
      if (installed.contains(component.id)) {
        logger.detail('Skipping ${component.id} (already installed)');
        _validateComponentInstallTargets(component);
        await _preflightNamespaceCollisions(component);
        await _writeLockfileRecord(component);
        return;
      }

      _validateComponentInstallTargets(component);
      await _preflightNamespaceCollisions(component);
      logger.action('Installing ${component.name} (${component.id})');
      _installingComponentIds.add(component.id);
      if (installDependencies) {
        for (final dep in component.dependsOn) {
          await addComponent(dep, ancestry: stack);
        }
      }

      if (enableSharedGroups) {
        for (final sharedId in component.shared) {
          await installShared(sharedId);
        }
      }

      if (component.pubspec.isNotEmpty) {
        final deps = component.pubspec['dependencies'] as Map<String, dynamic>;
        await _preflightDependencies(deps);
      }

      await _installComponentFiles(component);
      await _applyPlatformInstructions(component);
      final installedLocaleResources = await _installLocaleResources(component);

      if (component.pubspec.isNotEmpty) {
        final deps = component.pubspec['dependencies'] as Map<String, dynamic>;
        await _queueDependencyUpdates(deps);
      }
      if (component.assets.isNotEmpty) {
        await _queueAssetUpdates(component.assets);
      }
      if (component.fonts.isNotEmpty) {
        await _queueFontUpdates(component.fonts);
      }
      if (component.postInstall.isNotEmpty) {
        _reportPostInstall(component);
      }
      try {
        await _writeComponentManifest(
          component,
          localeResourcesInstalled: installedLocaleResources,
        );
      } catch (e) {
        if (e is ResolverV1Exception) {
          rethrow;
        }
        logger.warn('Failed to write component manifest: $e');
      }
      await _writeLockfileRecord(
        component,
        localeResourcesInstalled: installedLocaleResources,
      );
      _installedComponentCache?.add(component.id);
      if (!_deferAliases) {
        await generateAliases();
      }
      if (!_deferComponentManifest) {
        await _updateComponentManifest();
      }
      if (!_deferComponentManifest) {
        await _updateState();
      }
      if (!_deferDependencyUpdates) {
        await _syncDependenciesWithInstalled();
      }
    } catch (e, st) {
      if (!completer.isCompleted) {
        completer.completeError(e, st);
      }
      rethrow;
    } finally {
      _installingComponentIds.remove(component.id);
      _componentInstallTasks.remove(component.id);
      stack.remove(component.id);
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  Future<void> installAllComponents({int concurrency = 6}) async {
    await ensureInitFiles(allowPrompts: false);
    final ids = registry.components.map((c) => c.id).toList();
    if (ids.isEmpty) {
      return;
    }
    await RegistryDependencyGraph(registry).validateComponentInstall(ids);

    var index = 0;
    Future<void> worker() async {
      while (true) {
        if (index >= ids.length) {
          break;
        }
        final id = ids[index++];
        await addComponent(id, installDependencies: false);
      }
    }

    final workerCount = concurrency.clamp(1, ids.length);
    await Future.wait(List.generate(workerCount, (_) => worker()));
  }
}

final _classRegex = RegExp(
  r'^\s*(abstract\s+)?class\s+([A-Z]\w*)(\s*<[^>{}]+>)?',
  multiLine: true,
);

final _partRegex = RegExp(r'''part\s+['"]([^'"]+)['"];''');
