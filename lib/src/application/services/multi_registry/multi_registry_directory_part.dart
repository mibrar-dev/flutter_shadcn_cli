part of 'multi_registry_manager.dart';

extension MultiRegistryDirectoryPart on MultiRegistryManager {
  Future<void> _recordInlineExecution({
    required String projectRoot,
    required String namespace,
    required String category,
    required InitExecutionRecord record,
  }) async {
    if (record.filesWritten.isEmpty &&
        record.dirsCreated.isEmpty &&
        record.pubspecDelta.isEmpty) {
      return;
    }
    final journal = await InlineActionJournal.load(projectRoot);
    final updated = journal.append(
      namespace: namespace,
      entry: InlineActionJournalEntry(
        category: category,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        record: record,
      ),
    );
    await updated.save(projectRoot);
  }

  String _inlineAssetCategory({
    required bool installIcons,
    required bool installTypography,
    required bool installAll,
  }) {
    if (installAll || (installIcons && installTypography)) {
      return 'assets:all';
    }
    if (installTypography) {
      return 'assets:typography';
    }
    return 'assets:icons';
  }

  Future<List<RegistrySummary>> listRegistries() async {
    final projectRoot = findProjectRootFrom(targetDir);
    final config = await ShadcnConfig.load(projectRoot);
    final summaries = <String, RegistrySummary>{};

    final defaultNamespace = config.effectiveDefaultNamespace;
    final configRegistries =
        config.registries ?? const <String, RegistryConfigEntry>{};
    for (final entry in configRegistries.entries) {
      final namespace = entry.key;
      final value = entry.value;
      summaries[namespace] = RegistrySummary(
        namespace: namespace,
        displayName: namespace,
        isDefault: namespace == defaultNamespace,
        enabled: value.enabled,
        source: 'config',
        mode: value.registryMode,
        baseUrl: value.baseUrl ?? value.registryUrl,
        registryPath: value.registryPath,
        installRoot: value.installPath,
        capabilitySharedGroups: value.capabilitySharedGroups,
        capabilityComposites: value.capabilityComposites,
        capabilityTheme: value.capabilityTheme,
      );
    }

    try {
      final directory = await _loadDirectory();
      for (final entry in directory.registries) {
        final existing = summaries[entry.namespace];
        final mergedSource =
            existing == null ? 'directory' : 'config+directory';
        summaries[entry.namespace] = RegistrySummary(
          namespace: entry.namespace,
          displayName: entry.displayName,
          isDefault: entry.namespace == defaultNamespace,
          enabled: existing?.enabled ?? true,
          source: mergedSource,
          mode: existing?.mode ?? 'remote',
          baseUrl: existing?.baseUrl ?? entry.baseUrl,
          registryPath: existing?.registryPath,
          installRoot: existing?.installRoot ?? entry.installRoot,
          capabilitySharedGroups: existing?.capabilitySharedGroups ??
              entry.capabilities.sharedGroups,
          capabilityComposites:
              existing?.capabilityComposites ?? entry.capabilities.composites,
          capabilityTheme:
              existing?.capabilityTheme ?? entry.capabilities.theme,
        );
      }
    } catch (_) {
      // Directory lookup is optional for this listing command.
    }

    final list = summaries.values.toList()
      ..sort((a, b) => a.namespace.compareTo(b.namespace));
    return list;
  }

  Future<ShadcnConfig> setDefaultRegistry(String namespace) async {
    final trimmed = namespace.trim();
    if (trimmed.isEmpty) {
      throw MultiRegistryException('Registry namespace cannot be empty.');
    }

    final projectRoot = findProjectRootFrom(targetDir);
    var config = await ShadcnConfig.load(projectRoot);
    var entry = config.registryConfig(trimmed);

    if (entry == null) {
      final directory = await _loadDirectory();
      final directoryEntry = directory.registries.firstWhere(
        (item) => item.namespace == trimmed,
        orElse: () => throw MultiRegistryException(
          'Registry namespace "$trimmed" not found.',
        ),
      );
      config = await _upsertConfigFromDirectory(config, directoryEntry);
      entry = config.registryConfig(trimmed);
    }

    if (entry == null) {
      throw MultiRegistryException('Registry namespace "$trimmed" not found.');
    }

    config = config.copyWith(
      defaultNamespace: trimmed,
      registryMode: entry.registryMode ?? config.registryMode,
      registryPath: entry.registryPath ?? config.registryPath,
      registryUrl: entry.baseUrl ?? entry.registryUrl ?? config.registryUrl,
      installPath: entry.installPath ?? config.installPath,
      sharedPath: entry.sharedPath ?? config.sharedPath,
    );
    await ShadcnConfig.save(projectRoot, config);
    return config;
  }

  Future<Registry> _loadRegistryForSource(
    RegistrySource source, {
    required String projectRoot,
  }) async {
    final cacheKey =
        source.namespace.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (_registryCache.containsKey(cacheKey)) {
      return _registryCache[cacheKey]!;
    }

    final registry = await source.loadRegistry(
      projectRoot: projectRoot,
      offline: offline,
      skipIntegrity: skipIntegrity,
      logger: logger,
      directoryClient: directoryClient,
    );
    _registryCache[cacheKey] = registry;
    return registry;
  }

  Future<RegistrySource> _resolveSourceForNamespace(
    String namespace,
    ShadcnConfig config, {
    required bool allowDirectoryFallback,
  }) async {
    final cached = _sources[namespace];
    if (cached != null) {
      return cached;
    }

    final configEntry = config.registryConfig(namespace);
    RegistryDirectoryEntry? directoryEntry;
    try {
      final directory = await _loadDirectory();
      directoryEntry = directory.registries.firstWhere(
        (item) => item.namespace == namespace,
      );
    } catch (_) {
      directoryEntry = null;
    }

    final overrideSource = _sourceOverrideForNamespace(
      namespace: namespace,
      configEntry: configEntry,
      directoryEntry: directoryEntry,
    );
    if (overrideSource != null) {
      _sources[namespace] = overrideSource;
      return overrideSource;
    }

    if (configEntry != null &&
        ((configEntry.registryMode == 'local' &&
                configEntry.registryPath != null) ||
            configEntry.registryUrl != null ||
            configEntry.baseUrl != null)) {
      var effectiveEntry = directoryEntry == null
          ? configEntry
          : _mergeConfigWithDirectoryDefaults(configEntry, directoryEntry);
      final localPath = effectiveEntry.registryPath;
      if ((effectiveEntry.registryMode == 'local' || localPath != null) &&
          localPath != null &&
          localPath.isNotEmpty) {
        effectiveEntry = effectiveEntry.copyWith(
          componentsPath: _pathForLocalOverride(
            localRegistryPath: localPath,
            path: configEntry.componentsPath,
            fallback: directoryEntry?.componentsPath,
            detectComponentsManifest: true,
          ),
          componentsSchemaPath: _pathForLocalOverride(
            localRegistryPath: localPath,
            path: configEntry.componentsSchemaPath,
          ),
        );
      }
      final source = RegistrySource.fromConfig(
        namespace: namespace,
        configEntry: effectiveEntry,
      );
      _sources[namespace] = source;
      return source;
    }

    if (!allowDirectoryFallback) {
      throw MultiRegistryException(
          'Registry namespace "$namespace" is not configured.');
    }

    final entry = directoryEntry;
    if (entry == null) {
      throw MultiRegistryException(
        'Registry namespace "$namespace" not found in registries directory.',
      );
    }
    final source = RegistrySource.fromDirectory(entry);
    _sources[namespace] = source;
    return source;
  }

  RegistrySource? _sourceOverrideForNamespace({
    required String namespace,
    required RegistryConfigEntry? configEntry,
    required RegistryDirectoryEntry? directoryEntry,
  }) {
    final path = registryPathOverride?.trim();
    final url = registryUrlOverride?.trim();
    if (path != null && path.isNotEmpty) {
      final componentsPath = _pathForLocalOverride(
        localRegistryPath: path,
        path: configEntry?.componentsPath ?? directoryEntry?.componentsPath,
        fallback: 'components.json',
        detectComponentsManifest: true,
      );
      final componentsSchemaPath = _pathForLocalOverride(
        localRegistryPath: path,
        path: configEntry?.componentsSchemaPath ??
            directoryEntry?.componentsSchemaPath,
      );
      final installRoot = configEntry?.installPath ??
          directoryEntry?.installRoot ??
          'lib/ui/$namespace';
      final sharedRoot = configEntry?.sharedPath ?? '$installRoot/shared';
      return RegistrySource.fromConfig(
        namespace: namespace,
        configEntry: RegistryConfigEntry(
          registryMode: 'local',
          registryPath: path,
          componentsPath: componentsPath,
          componentsSchemaPath: componentsSchemaPath,
          installPath: installRoot,
          sharedPath: sharedRoot,
          capabilitySharedGroups: configEntry?.capabilitySharedGroups ??
              directoryEntry?.capabilities.sharedGroups,
          capabilityComposites: configEntry?.capabilityComposites ??
              directoryEntry?.capabilities.composites,
          capabilityTheme: configEntry?.capabilityTheme ??
              directoryEntry?.capabilities.theme,
          enabled: configEntry?.enabled ?? true,
        ),
      );
    }
    if (url != null && url.isNotEmpty) {
      final installRoot = configEntry?.installPath ??
          directoryEntry?.installRoot ??
          'lib/ui/$namespace';
      final sharedRoot = configEntry?.sharedPath ?? '$installRoot/shared';
      return RegistrySource.fromConfig(
        namespace: namespace,
        configEntry: RegistryConfigEntry(
          registryMode: 'remote',
          registryUrl: url,
          baseUrl: url,
          componentsPath:
              configEntry?.componentsPath ?? directoryEntry?.componentsPath,
          componentsSchemaPath: configEntry?.componentsSchemaPath ??
              directoryEntry?.componentsSchemaPath,
          installPath: installRoot,
          sharedPath: sharedRoot,
          capabilitySharedGroups: configEntry?.capabilitySharedGroups ??
              directoryEntry?.capabilities.sharedGroups,
          capabilityComposites: configEntry?.capabilityComposites ??
              directoryEntry?.capabilities.composites,
          capabilityTheme: configEntry?.capabilityTheme ??
              directoryEntry?.capabilities.theme,
          enabled: configEntry?.enabled ?? true,
        ),
      );
    }
    return null;
  }

  String _inlineActionBaseUrl({
    required RegistryDirectoryEntry entry,
    required RegistryConfigEntry? configEntry,
  }) {
    final path = registryPathOverride?.trim();
    if (path != null && path.isNotEmpty) {
      return _localOverrideSourceRoot(path);
    }
    final url = registryUrlOverride?.trim();
    if (url != null && url.isNotEmpty) {
      return url;
    }
    return configEntry?.baseUrl ?? configEntry?.registryUrl ?? entry.baseUrl;
  }

  String _localOverrideSourceRoot(String path) {
    final normalized = _resolveLocalOverridePath(path);
    if (p.basename(normalized) == 'registry') {
      return p.dirname(normalized);
    }
    return normalized;
  }

  String _resolveLocalOverridePath(String path) {
    final trimmed = path.trim();
    if (p.isAbsolute(trimmed)) {
      return p.normalize(trimmed);
    }
    return p.normalize(p.join(findProjectRootFrom(targetDir), trimmed));
  }

  String? _pathForLocalOverride({
    required String localRegistryPath,
    required String? path,
    String? fallback,
    bool detectComponentsManifest = false,
  }) {
    final value = path ??
        (detectComponentsManifest
            ? _detectLocalOverridePath(localRegistryPath)
            : null) ??
        fallback;
    if (value == null || value.isEmpty) {
      return null;
    }
    final normalizedLocal = _resolveLocalOverridePath(localRegistryPath);
    if (p.basename(normalizedLocal) == 'registry' &&
        value.startsWith('registry/')) {
      return value.substring('registry/'.length);
    }
    return value;
  }

  String? _detectLocalOverridePath(String localRegistryPath) {
    final localRoot = _resolveLocalOverridePath(localRegistryPath);
    for (final candidate in const [
      'manifests/components.json',
      'components.json',
    ]) {
      if (File(p.join(localRoot, candidate)).existsSync()) {
        return candidate;
      }
    }
    final sourceRoot = _localOverrideSourceRoot(localRegistryPath);
    final candidates = <String>[
      'registry/manifests/components.json',
      'manifests/components.json',
      'components.json',
    ];
    for (final candidate in candidates) {
      if (File(p.join(sourceRoot, candidate)).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  Future<ShadcnConfig> _upsertConfigFromDirectory(
    ShadcnConfig config,
    RegistryDirectoryEntry entry,
  ) async {
    final installRoot = entry.installRoot;
    final sharedRoot = '$installRoot/shared';
    final existing = config.registryConfig(entry.namespace);
    final next = config.withRegistry(
      entry.namespace,
      existing?.copyWith(
            registryMode: existing.registryMode ?? 'remote',
            registryUrl: existing.registryUrl ?? entry.baseUrl,
            baseUrl: existing.baseUrl ?? entry.baseUrl,
            componentsPath: existing.componentsPath ?? entry.componentsPath,
            componentsSchemaPath:
                existing.componentsSchemaPath ?? entry.componentsSchemaPath,
            indexPath: existing.indexPath ?? entry.indexPath,
            indexSchemaPath: existing.indexSchemaPath ?? entry.indexSchemaPath,
            themesPath: existing.themesPath ?? entry.themesPath,
            themesSchemaPath:
                existing.themesSchemaPath ?? entry.themesSchemaPath,
            themeConverterDartPath:
                existing.themeConverterDartPath ?? entry.themeConverterDartPath,
            installPath: existing.installPath ?? installRoot,
            sharedPath: existing.sharedPath ?? sharedRoot,
            enabled: true,
          ) ??
          RegistryConfigEntry(
            registryMode: 'remote',
            registryUrl: entry.baseUrl,
            baseUrl: entry.baseUrl,
            componentsPath: entry.componentsPath,
            componentsSchemaPath: entry.componentsSchemaPath,
            indexPath: entry.indexPath,
            indexSchemaPath: entry.indexSchemaPath,
            themesPath: entry.themesPath,
            themesSchemaPath: entry.themesSchemaPath,
            themeConverterDartPath: entry.themeConverterDartPath,
            installPath: installRoot,
            sharedPath: sharedRoot,
            enabled: true,
          ),
    );
    return next;
  }

  RegistryConfigEntry _mergeConfigWithDirectoryDefaults(
    RegistryConfigEntry configEntry,
    RegistryDirectoryEntry directoryEntry,
  ) {
    return configEntry.copyWith(
      baseUrl: configEntry.baseUrl ?? directoryEntry.baseUrl,
      registryUrl: configEntry.registryUrl ?? directoryEntry.baseUrl,
      componentsPath:
          configEntry.componentsPath ?? directoryEntry.componentsPath,
      componentsSchemaPath: configEntry.registryPath == null
          ? configEntry.componentsSchemaPath ??
              directoryEntry.componentsSchemaPath
          : configEntry.componentsSchemaPath,
      indexPath: configEntry.indexPath ?? directoryEntry.indexPath,
      indexSchemaPath:
          configEntry.indexSchemaPath ?? directoryEntry.indexSchemaPath,
      themesPath: configEntry.themesPath ?? directoryEntry.themesPath,
      themesSchemaPath:
          configEntry.themesSchemaPath ?? directoryEntry.themesSchemaPath,
      folderStructurePath:
          configEntry.folderStructurePath ?? directoryEntry.folderStructurePath,
      metaPath: configEntry.metaPath ?? directoryEntry.metaPath,
      themeConverterDartPath: configEntry.themeConverterDartPath ??
          directoryEntry.themeConverterDartPath,
      capabilitySharedGroups: configEntry.capabilitySharedGroups ??
          directoryEntry.capabilities.sharedGroups,
      capabilityComposites: configEntry.capabilityComposites ??
          directoryEntry.capabilities.composites,
      capabilityTheme:
          configEntry.capabilityTheme ?? directoryEntry.capabilities.theme,
      trustMode: configEntry.trustMode ?? directoryEntry.trust.mode,
      trustSha256: configEntry.trustSha256 ?? directoryEntry.trust.sha256,
    );
  }

  Future<RegistryDirectory> _loadDirectory() async {
    if (_directoryCache != null) {
      return _directoryCache!;
    }
    _directoryCache = await directoryClient.load(
      projectRoot: targetDir,
      directoryUrl: directoryUrl,
      directoryPath: directoryPath,
      offline: offline,
      currentCliVersion: VersionManager.currentVersion,
      logger: logger,
    );
    return _directoryCache!;
  }
}
