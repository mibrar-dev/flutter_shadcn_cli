part of 'multi_registry_manager.dart';

extension MultiRegistryInitPart on MultiRegistryManager {
  Future<bool> canHandleNamespaceInit(String namespace) async {
    final trimmed = namespace.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    final config = await _loadProjectConfig();
    final byConfig = config.registryConfig(trimmed);
    if (byConfig != null) {
      return true;
    }
    final directory = await _loadDirectory();
    return directory.registries.any((entry) => entry.namespace == trimmed);
  }

  Future<void> runNamespaceInit(
    String namespace, {
    bool assumeYes = false,
  }) async {
    final projectRoot = _projectRoot;
    var config = await _loadProjectConfig();
    RegistryDirectoryEntry? directoryEntry;
    try {
      final directory = await _loadDirectory();
      directoryEntry = directory.registries.firstWhere(
        (entry) => entry.namespace == namespace,
      );
    } on StateError {
      directoryEntry = null;
    }
    final configured = config.registryConfig(namespace);
    final source = directoryEntry != null
        ? (configured != null ||
                (registryPathOverride?.trim().isNotEmpty ?? false) ||
                (registryUrlOverride?.trim().isNotEmpty ?? false)
            ? await _resolveSourceForNamespace(
                namespace,
                config,
                allowDirectoryFallback: true,
              )
            : RegistrySource.fromDirectory(directoryEntry))
        : await _resolveSourceForNamespace(
            namespace,
            config,
            allowDirectoryFallback: true,
          );
    await _validateRegistryForNamespaceInit(source, projectRoot: projectRoot);
    if (directoryEntry != null) {
      config = await _upsertConfigFromDirectory(config, directoryEntry);
    }
    config = await _maybePromptInstallPath(
      config: config,
      namespace: namespace,
      source: source,
      assumeYes: assumeYes,
    );
    config = await _maybePromptSharedPath(
      config: config,
      namespace: namespace,
      source: source,
      capabilities: directoryEntry?.capabilities,
      assumeYes: assumeYes,
    );
    await _saveProjectConfig(config);
    await _ensureAnalysisOptionsExclude(
      projectRoot: projectRoot,
      installPath:
          config.registryConfig(namespace)?.installPath ?? source.installRoot,
    );

    if (directoryEntry == null) {
      logger.info('No bootstrap actions defined for this registry.');
      return;
    }

    final updatedConfigured = config.registryConfig(namespace);
    final overrideBaseUrl = _inlineActionBaseUrl(
      entry: directoryEntry,
      configEntry: updatedConfigured,
    );
    final initEntry = overrideBaseUrl.isNotEmpty
        ? RegistryDirectoryEntry(
            id: directoryEntry.id,
            displayName: directoryEntry.displayName,
            minCliVersion: directoryEntry.minCliVersion,
            baseUrl: overrideBaseUrl,
            namespace: directoryEntry.namespace,
            installRoot: directoryEntry.installRoot,
            paths: directoryEntry.paths,
            capabilities: directoryEntry.capabilities,
            trust: directoryEntry.trust,
            init: directoryEntry.init,
            raw: directoryEntry.raw,
          )
        : directoryEntry;

    final result = await initActionEngine.executeRegistryInit(
      projectRoot: projectRoot,
      registry: initEntry,
      logger: logger,
      optionalActionDecider: (action) async => _shouldRunOptionalInitAction(
        action: action,
        assumeYes: assumeYes,
      ),
      groupSelector: (action, groups) async => _selectInitActionGroups(
        action: action,
        groups: groups,
        assumeYes: assumeYes,
      ),
    );
    await _recordInlineExecution(
      projectRoot: projectRoot,
      namespace: namespace,
      category: 'init',
      record: result.record,
    );

    final state = await ShadcnState.load(
      projectRoot,
      defaultNamespace: config.effectiveDefaultNamespace,
    );
    final merged = Map<String, RegistryStateEntry>.from(
      state.registries ?? const {},
    );
    merged[namespace] = RegistryStateEntry(
      installPath: source.installRoot,
      sharedPath: source.sharedRoot,
      themeId: state.themeId,
    );
    await ShadcnState.save(
      projectRoot,
      ShadcnState(
        installPath: state.installPath ?? source.installRoot,
        sharedPath: state.sharedPath ?? source.sharedRoot,
        themeId: state.themeId,
        managedDependencies: state.managedDependencies,
        registries: merged,
      ),
    );

    if (!initEntry.hasInlineInit) {
      logger.info('No bootstrap actions defined for this registry.');
    } else {
      logger.success(
        'Initialized ${source.namespace} (${result.filesWritten} files, ${result.dirsCreated} dirs).',
      );
    }

    await _resolveInitTheme(
      projectRoot: projectRoot,
      namespace: namespace,
      registryEntry: initEntry,
      config: config,
      assumeYes: assumeYes,
    );
  }

  Future<void> _ensureAnalysisOptionsExclude({
    required String projectRoot,
    required String installPath,
  }) async {
    final normalizedInstallPath = installPath.replaceAll('\\', '/');
    final excludedPath = normalizedInstallPath.endsWith('/**')
        ? normalizedInstallPath
        : '$normalizedInstallPath/**';
    final file = File(p.join(projectRoot, 'analysis_options.yaml'));
    if (!await file.exists()) {
      await file.writeAsString(
        [
          'include: package:flutter_lints/flutter.yaml',
          '',
          'analyzer:',
          '  exclude:',
          '    # Vendored shadcn install output. Analyze the canonical registry package instead.',
          '    - $excludedPath',
          '',
        ].join('\n'),
      );
      return;
    }

    final content = await file.readAsString();
    if (content.contains(excludedPath)) {
      return;
    }

    final lines = content.split('\n');
    final analyzerIndex = lines.indexWhere(
      (line) => RegExp(r'^analyzer:\s*$').hasMatch(line),
    );
    if (analyzerIndex == -1) {
      final prefix = content.endsWith('\n') ? content : '$content\n';
      await file.writeAsString(
        [
          prefix,
          'analyzer:',
          '  exclude:',
          '    # Vendored shadcn install output. Analyze the canonical registry package instead.',
          '    - $excludedPath',
          '',
        ].join('\n'),
      );
      return;
    }

    var analyzerEnd = lines.length;
    for (var i = analyzerIndex + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty || line.startsWith(' ') || line.startsWith('#')) {
        continue;
      }
      analyzerEnd = i;
      break;
    }

    final excludeIndex = () {
      for (var i = analyzerIndex + 1; i < analyzerEnd; i++) {
        if (RegExp(r'^\s{2}exclude:\s*$').hasMatch(lines[i])) {
          return i;
        }
      }
      return -1;
    }();

    if (excludeIndex == -1) {
      lines.insertAll(analyzerEnd, [
        '  exclude:',
        '    # Vendored shadcn install output. Analyze the canonical registry package instead.',
        '    - $excludedPath',
      ]);
    } else {
      var insertIndex = excludeIndex + 1;
      while (insertIndex < analyzerEnd &&
          (RegExp(r'^\s{4}-\s+').hasMatch(lines[insertIndex]) ||
              lines[insertIndex].trim().isEmpty ||
              RegExp(r'^\s{4}#').hasMatch(lines[insertIndex]))) {
        insertIndex++;
      }
      lines.insertAll(insertIndex, [
        '    # Vendored shadcn install output. Analyze the canonical registry package instead.',
        '    - $excludedPath',
      ]);
    }

    await file.writeAsString(lines.join('\n'));
  }

  Future<ShadcnConfig> _maybePromptSharedPath({
    required ShadcnConfig config,
    required String namespace,
    required RegistrySource source,
    required RegistryCapabilities? capabilities,
    required bool assumeYes,
  }) async {
    final supportsSharedGroups = capabilities?.sharedGroups ?? false;
    if (!supportsSharedGroups || assumeYes) {
      return config;
    }
    final current = config.registryConfig(namespace);
    final defaultPath = (current?.sharedPath?.trim().isNotEmpty ?? false)
        ? current!.sharedPath!.trim()
        : source.sharedRoot;
    stdout.write('Shared files path (default: $defaultPath). Enter to keep: ');
    final input = stdin.readLineSync()?.trim() ?? '';
    final nextPath = input.isEmpty ? defaultPath : input;
    final registries =
        Map<String, RegistryConfigEntry>.from(config.registries ?? {});
    final nextEntry = (current ?? const RegistryConfigEntry()).copyWith(
      sharedPath: nextPath,
      installPath: current?.installPath ?? source.installRoot,
      enabled: current?.enabled ?? true,
    );
    registries[namespace] = nextEntry;
    return config.copyWith(registries: registries);
  }

  Future<ShadcnConfig> _maybePromptInstallPath({
    required ShadcnConfig config,
    required String namespace,
    required RegistrySource source,
    required bool assumeYes,
  }) async {
    if (assumeYes) {
      return config;
    }
    final current = config.registryConfig(namespace);
    final defaultPath = (current?.installPath?.trim().isNotEmpty ?? false)
        ? current!.installPath!.trim()
        : source.installRoot;
    stdout.write(
      'Component install path inside lib/ (e.g. lib/ui/shadcn or lib/pages/docs) (default: $defaultPath). Enter to keep: ',
    );
    final input = stdin.readLineSync()?.trim() ?? '';
    final nextPath = input.isEmpty ? defaultPath : input;
    final sharedDefault = (current?.sharedPath?.trim().isNotEmpty ?? false)
        ? current!.sharedPath!.trim()
        : source.sharedRoot;
    final registries =
        Map<String, RegistryConfigEntry>.from(config.registries ?? {});
    final nextEntry = (current ?? const RegistryConfigEntry()).copyWith(
      installPath: nextPath,
      sharedPath: sharedDefault,
      enabled: current?.enabled ?? true,
    );
    registries[namespace] = nextEntry;
    return config.copyWith(registries: registries);
  }

  Future<void> _validateRegistryForNamespaceInit(
    RegistrySource source, {
    required String projectRoot,
  }) async {
    if (skipIntegrity) {
      logger.warn(
        'components.json validation skipped for init (${source.namespace}).',
      );
      return;
    }
    await _loadRegistryForSource(source, projectRoot: projectRoot);
  }

  Future<void> _resolveInitTheme({
    required String projectRoot,
    required String namespace,
    required RegistryDirectoryEntry registryEntry,
    required ShadcnConfig config,
    required bool assumeYes,
  }) async {
    try {
      final supportsTheme = registryEntry.capabilities.theme;
      final themesPath = registryEntry.themesPath?.trim();
      if (!supportsTheme || themesPath == null || themesPath.isEmpty) {
        return;
      }

      final themeRegistryBaseUrl = _inlineActionBaseUrl(
        entry: registryEntry,
        configEntry: config.registryConfig(namespace),
      );
      final registryId = _themeRegistryId(namespace, themeRegistryBaseUrl);
      final cacheRoot = ProjectPathGuard.resolveSafeWritePath(
        projectRoot: projectRoot,
        destinationRelativePath:
            p.join('.shadcn', 'cache', 'registry', registryId),
      );
      final indexLoader = ThemeIndexLoader(
        registryId: registryId,
        registryBaseUrl: themeRegistryBaseUrl,
        themesPath: themesPath,
        themesSchemaPath: registryEntry.themesSchemaPath,
        refresh: false,
        offline: offline,
        logger: logger,
        cacheRootPath: cacheRoot,
      );
      final indexData = await indexLoader.load();
      final entries = indexLoader.entriesFrom(indexData);
      if (entries.isEmpty) {
        logger.info('No theme presets available for @$namespace.');
        return;
      }

      final selected = assumeYes
          ? _defaultThemeEntry(indexData, entries)
          : _promptThemeSelection(
              namespace: namespace, entries: entries, indexData: indexData);
      if (selected == null) {
        logger.info('Skipping theme selection.');
        return;
      }

      final source = await _resolveSourceForNamespace(
        namespace,
        config,
        allowDirectoryFallback: true,
      );
      final registry =
          await _loadRegistryForSource(source, projectRoot: projectRoot);
      final installer = Installer(
        registry: registry,
        targetDir: projectRoot,
        logger: logger,
        installPathOverride: source.installRoot,
        sharedPathOverride: source.sharedRoot,
        stateNamespace: namespace,
        registryNamespace: namespace,
        registryBaseUrlOverride: themeRegistryBaseUrl,
        themesPathOverride: themesPath,
        themesSchemaPathOverride: registryEntry.themesSchemaPath,
        enableSharedGroups: registryEntry.capabilities.sharedGroups,
        enableComposites: registryEntry.capabilities.composites,
      );
      await installer.applyThemeById(selected.id);
    } catch (e) {
      logger.warn('Skipping theme selection for @$namespace: $e');
    }
  }

  Future<bool> _shouldRunOptionalInitAction({
    required Map<String, dynamic> action,
    required bool assumeYes,
  }) async {
    if (assumeYes) {
      return false;
    }
    final label = action['promptLabel']?.toString().trim();
    if (label == null || label.isEmpty) {
      return false;
    }
    final description = action['promptDescription']?.toString().trim();
    stdout.writeln(label);
    if (description != null && description.isNotEmpty) {
      stdout.writeln(description);
    }
    stdout.write('Install? [Y/n]: ');
    final input = stdin.readLineSync()?.trim().toLowerCase();
    if (input == null || input.isEmpty) {
      return true;
    }
    return input == 'y' || input == 'yes';
  }

  Future<List<Map<String, dynamic>>> _selectInitActionGroups({
    required Map<String, dynamic> action,
    required List<Map<String, dynamic>> groups,
    required bool assumeYes,
  }) async {
    if (groups.isEmpty) {
      return const [];
    }
    if (assumeYes) {
      return groups.where((group) => group['required'] == true).toList();
    }
    final label = action['promptLabel']?.toString().trim();
    final description = action['promptDescription']?.toString().trim();
    if (label != null && label.isNotEmpty) {
      stdout.writeln(label);
    }
    if (description != null && description.isNotEmpty) {
      stdout.writeln(description);
    }
    stdout.writeln(
        'Select groups (comma-separated numbers, Enter for defaults):');
    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      final suffix = group['default'] == false ? '' : ' [default]';
      stdout.writeln('  ${i + 1}) ${group['label']}$suffix');
      final groupDescription = group['description']?.toString().trim();
      if (groupDescription != null && groupDescription.isNotEmpty) {
        stdout.writeln('     $groupDescription');
      }
    }
    stdout.write('Groups: ');
    final input = stdin.readLineSync()?.trim() ?? '';
    if (input.isEmpty) {
      return groups.where((group) => group['default'] != false).toList();
    }
    final selected = <Map<String, dynamic>>[];
    for (final token in input.split(',')) {
      final index = int.tryParse(token.trim());
      if (index == null || index < 1 || index > groups.length) {
        continue;
      }
      selected.add(groups[index - 1]);
    }
    return selected;
  }

  ThemeIndexEntry _defaultThemeEntry(
    Map<String, dynamic> indexData,
    List<ThemeIndexEntry> entries,
  ) {
    final defaultId = indexData['default']?.toString().trim();
    if (defaultId != null && defaultId.isNotEmpty) {
      for (final entry in entries) {
        if (entry.id == defaultId) {
          return entry;
        }
      }
    }
    final raw = indexData['themes'] ?? indexData['items'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map && item['default'] == true) {
          final id = item['id']?.toString();
          if (id != null) {
            for (final entry in entries) {
              if (entry.id == id) {
                return entry;
              }
            }
          }
        }
      }
    }
    return entries.first;
  }

  ThemeIndexEntry? _promptThemeSelection({
    required String namespace,
    required List<ThemeIndexEntry> entries,
    required Map<String, dynamic> indexData,
  }) {
    logger
        .info('Select a starter theme for @$namespace (press Enter to skip):');
    for (var i = 0; i < entries.length; i++) {
      final preset = entries[i];
      logger.info('  ${i + 1}) ${preset.name} (${preset.id})');
    }
    stdout.write('Theme number: ');
    final input = stdin.readLineSync()?.trim();
    if (input == null || input.isEmpty) {
      return null;
    }
    final index = int.tryParse(input);
    if (index != null && index >= 1 && index <= entries.length) {
      return entries[index - 1];
    }
    for (final entry in entries) {
      if (entry.id == input) {
        return entry;
      }
    }
    final defaultEntry = _defaultThemeEntry(indexData, entries);
    logger.warn('Invalid theme selection. Using default: ${defaultEntry.id}.');
    return defaultEntry;
  }

  String _themeRegistryId(String namespace, String baseUrl) {
    final key = '$namespace:$baseUrl';
    return key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }
}
