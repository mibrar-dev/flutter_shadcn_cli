part of 'multi_registry_manager.dart';

extension MultiRegistryDirectoryPart on MultiRegistryManager {
  Future<RegistryDirectoryEntry?> findRegistryEntry(String namespace) async {
    final trimmed = namespace.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final directory = await _loadDirectory();
      return directory.registries.firstWhere(
        (item) => item.namespace == trimmed,
      );
    } on StateError {
      return null;
    }
  }

  Future<DiscoveryRegistryTarget> resolveDiscoveryTarget({
    String? namespace,
  }) async {
    final projectRoot = findProjectRootFrom(targetDir);
    final config = await ShadcnConfig.load(projectRoot);
    final resolvedNamespace = namespace?.trim().isNotEmpty == true
        ? namespace!.trim()
        : config.effectiveDefaultNamespace;
    final source = await _resolveSourceForNamespace(
      resolvedNamespace,
      config,
      allowDirectoryFallback: true,
    );
    final registryBase = _discoveryRegistryBaseForSource(
      projectRoot: projectRoot,
      source: source,
    );
    final indexPath = _discoveryIndexPathForSource(source);
    final indexSchemaPath = _discoveryIndexSchemaPathForSource(source);
    return DiscoveryRegistryTarget(
      namespace: resolvedNamespace,
      registryBase: registryBase,
      registryId: _discoveryRegistryId(registryBase),
      indexPath: indexPath,
      indexSchemaPath: indexSchemaPath,
    );
  }

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

  String _discoveryRegistryBaseForSource({
    required String projectRoot,
    required RegistrySource source,
  }) {
    final configEntry = source.configEntry;
    if (configEntry != null &&
        ((configEntry.registryMode == 'local' &&
                configEntry.registryPath != null) ||
            configEntry.registryPath != null)) {
      final localRoot = RegistrySource.resolveLocalPath(
        projectRoot,
        configEntry.registryPath,
      );
      if (localRoot == null || localRoot.isEmpty) {
        throw MultiRegistryException(
          'Local registry path is not configured for namespace "${source.namespace}".',
        );
      }
      return localRoot;
    }

    final remoteRoot = configEntry?.baseUrl ??
        configEntry?.registryUrl ??
        source.directoryEntry?.baseUrl;
    if (remoteRoot == null || remoteRoot.isEmpty) {
      throw MultiRegistryException(
        'Remote registry URL is not configured for namespace "${source.namespace}".',
      );
    }
    return remoteRoot;
  }

  String _discoveryRegistryId(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safe.length > 80) {
      return safe.substring(0, 80);
    }
    return safe;
  }

  String _discoveryIndexPathForSource(RegistrySource source) {
    final configEntry = source.configEntry;
    final directoryEntry = source.directoryEntry;
    final localPath = configEntry?.registryPath;
    if (localPath != null && localPath.isNotEmpty) {
      return _pathForLocalOverride(
            localRegistryPath: localPath,
            path: configEntry?.indexPath ?? directoryEntry?.indexPath,
            fallback: 'index.json',
          ) ??
          'index.json';
    }
    return configEntry?.indexPath ?? directoryEntry?.indexPath ?? 'index.json';
  }

  String? _discoveryIndexSchemaPathForSource(RegistrySource source) {
    final configEntry = source.configEntry;
    final directoryEntry = source.directoryEntry;
    final localPath = configEntry?.registryPath;
    if (localPath != null && localPath.isNotEmpty) {
      return _pathForLocalOverride(
        localRegistryPath: localPath,
        path: configEntry?.indexSchemaPath ?? directoryEntry?.indexSchemaPath,
      );
    }
    return configEntry?.indexSchemaPath ?? directoryEntry?.indexSchemaPath;
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

  Future<ShadcnConfig> configureDefaultRegistryLocal(
    String namespace, {
    required String registriesPath,
    required String registryPath,
  }) async {
    final trimmed = namespace.trim();
    final trimmedRegistriesPath = registriesPath.trim();
    final trimmedRegistryPath = registryPath.trim();
    if (trimmed.isEmpty) {
      throw MultiRegistryException('Registry namespace cannot be empty.');
    }
    if (trimmedRegistriesPath.isEmpty) {
      throw MultiRegistryException('Registries path cannot be empty.');
    }
    if (trimmedRegistryPath.isEmpty) {
      throw MultiRegistryException('Registry path cannot be empty.');
    }

    final projectRoot = findProjectRootFrom(targetDir);
    var config = await ShadcnConfig.load(projectRoot);
    final directory = await directoryClient.load(
      projectRoot: projectRoot,
      directoryPath: trimmedRegistriesPath,
      offline: offline,
      currentCliVersion: VersionManager.currentVersion,
      logger: logger,
    );
    final directoryEntry = directory.registries.firstWhere(
      (item) => item.namespace == trimmed,
      orElse: () => throw MultiRegistryException(
        'Registry namespace "$trimmed" not found in $trimmedRegistriesPath.',
      ),
    );

    config = await _upsertConfigFromDirectory(config, directoryEntry);
    final existing =
        config.registryConfig(trimmed) ?? const RegistryConfigEntry();
    final localEntry = existing.copyWith(
      registryMode: 'local',
      registryPath: trimmedRegistryPath,
      registryUrl: null,
      enabled: true,
    );
    config = config.withRegistry(trimmed, localEntry).copyWith(
          defaultNamespace: trimmed,
          registriesPath: trimmedRegistriesPath,
          registryMode: 'local',
          registryPath: trimmedRegistryPath,
          registryUrl: null,
          installPath: localEntry.installPath ?? config.installPath,
          sharedPath: localEntry.sharedPath ?? config.sharedPath,
        );
    await ShadcnConfig.save(projectRoot, config);
    return config;
  }

  Future<ShadcnConfig> configureDefaultRegistryRemote(String namespace) async {
    final trimmed = namespace.trim();
    if (trimmed.isEmpty) {
      throw MultiRegistryException('Registry namespace cannot be empty.');
    }

    final projectRoot = findProjectRootFrom(targetDir);
    var config = await ShadcnConfig.load(projectRoot);
    final directory = await directoryClient.load(
      projectRoot: projectRoot,
      directoryUrl: defaultRegistriesDirectoryUrl,
      directoryPath: null,
      offline: offline,
      currentCliVersion: VersionManager.currentVersion,
      logger: logger,
    );
    final directoryEntry = directory.registries.firstWhere(
      (item) => item.namespace == trimmed,
      orElse: () => throw MultiRegistryException(
        'Registry namespace "$trimmed" not found.',
      ),
    );

    config = await _upsertConfigFromDirectory(config, directoryEntry);
    final existing =
        config.registryConfig(trimmed) ?? const RegistryConfigEntry();
    final remoteEntry = existing.copyWith(
      registryMode: 'remote',
      registryPath: null,
      registryUrl: directoryEntry.baseUrl,
      baseUrl: directoryEntry.baseUrl,
      enabled: true,
    );
    config = config.withRegistry(trimmed, remoteEntry).copyWith(
          defaultNamespace: trimmed,
          registriesPath: null,
          registryMode: 'remote',
          registryPath: null,
          registryUrl: directoryEntry.baseUrl,
          installPath: remoteEntry.installPath ?? config.installPath,
          sharedPath: remoteEntry.sharedPath ?? config.sharedPath,
        );
    await ShadcnConfig.save(projectRoot, config);
    return config;
  }

  Future<Registry> _loadRegistryForSource(
    RegistrySource source, {
    required String projectRoot,
  }) async {
    final cacheKey =
        _registryCacheKeyForSource(source, projectRoot: projectRoot);
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

  String _registryCacheKeyForSource(
    RegistrySource source, {
    required String projectRoot,
  }) {
    final entry = source.configEntry;
    final directoryEntry = source.directoryEntry;
    final mode = entry?.registryMode ??
        (entry?.registryPath != null ? 'local' : 'remote');
    final root = entry?.registryPath != null
        ? RegistrySource.resolveLocalPath(projectRoot, entry!.registryPath) ??
            ''
        : (entry?.baseUrl ??
            entry?.registryUrl ??
            directoryEntry?.baseUrl ??
            '');
    final manifestPath = entry?.componentsPath ??
        directoryEntry?.componentsPath ??
        'components.json';
    final schemaPath = entry?.componentsSchemaPath ??
        directoryEntry?.componentsSchemaPath ??
        '';
    final rawKey = '${source.namespace}|$mode|$root|$manifestPath|$schemaPath';
    return rawKey.replaceAll(RegExp(r'[^A-Za-z0-9._|/-]'), '_');
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
    final earlyOverrideSource = _sourceOverrideForNamespace(
      namespace: namespace,
      configEntry: configEntry,
      directoryEntry: null,
    );
    if (earlyOverrideSource != null) {
      _sources[namespace] = earlyOverrideSource;
      return earlyOverrideSource;
    }

    RegistryDirectoryEntry? directoryEntry;
    try {
      final directory = await _loadDirectory();
      directoryEntry = directory.registries.firstWhere(
        (item) => item.namespace == namespace,
      );
    } on StateError {
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
            configEntry.registryPath != null)) {
      final localPath = configEntry.registryPath;
      final effectiveEntry = configEntry.copyWith(
        componentsPath: _pathForLocalOverride(
          localRegistryPath: localPath!,
          path: configEntry.componentsPath,
          fallback: 'components.json',
          detectComponentsManifest: true,
        ),
        componentsSchemaPath: _pathForLocalOverride(
          localRegistryPath: localPath,
          path: configEntry.componentsSchemaPath,
        ),
        indexPath: _pathForLocalOverride(
          localRegistryPath: localPath,
          path: configEntry.indexPath,
          fallback: 'index.json',
        ),
        indexSchemaPath: _pathForLocalOverride(
          localRegistryPath: localPath,
          path: configEntry.indexSchemaPath,
        ),
      );
      final source = RegistrySource.fromConfig(
        namespace: namespace,
        configEntry: effectiveEntry,
      );
      _sources[namespace] = source;
      return source;
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
      final indexPath = _pathForLocalOverride(
        localRegistryPath: path,
        path: configEntry?.indexPath ?? directoryEntry?.indexPath,
        fallback: 'index.json',
      );
      final indexSchemaPath = _pathForLocalOverride(
        localRegistryPath: path,
        path: configEntry?.indexSchemaPath ?? directoryEntry?.indexSchemaPath,
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
          indexPath: indexPath,
          indexSchemaPath: indexSchemaPath,
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
          indexPath: configEntry?.indexPath ?? directoryEntry?.indexPath,
          indexSchemaPath:
              configEntry?.indexSchemaPath ?? directoryEntry?.indexSchemaPath,
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
    final configuredPath = configEntry?.registryPath?.trim();
    if ((configEntry?.registryMode == 'local' || configuredPath != null) &&
        configuredPath != null &&
        configuredPath.isNotEmpty) {
      return _resolveLocalOverridePath(configuredPath);
    }
    final path = registryPathOverride?.trim();
    if (path != null && path.isNotEmpty) {
      return _resolveLocalOverridePath(path);
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
