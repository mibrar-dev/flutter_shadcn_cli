part of 'installer.dart';

extension InstallerThemePart on Installer {
  Future<void> _promptThemeSelection() async {
    await _interactiveThemeSelection(skipIfConfigured: true);
  }

  Future<void> chooseTheme({bool refresh = false}) async {
    await _interactiveThemeSelection(
      skipIfConfigured: false,
      refresh: refresh,
    );
  }

  Future<void> listThemes({bool refresh = false}) async {
    final presets = await _loadResolvedThemePresets(refresh: refresh);
    if (presets.isEmpty) {
      logger.info('No theme presets available.');
      return;
    }
    final config = await ShadcnConfig.load(targetDir);
    final currentTheme = config.themeId;
    logger.info('Installed theme presets:');
    for (var i = 0; i < presets.length; i++) {
      final preset = presets[i];
      final marker = preset.id == currentTheme ? ' (current)' : '';
      logger.info('  ${i + 1}) ${preset.name} (${preset.id})$marker');
    }
  }

  Future<void> listWidgetThemes({bool refresh = false}) async {
    try {
      final resolved = await _resolveWidgetThemeRegistry(refresh: refresh);
      if (resolved == null) {
        logger.info('This registry does not provide widget theme metadata.');
        return;
      }
      if (resolved.entries.isEmpty) {
        logger.info('No themeable widgets available.');
        return;
      }
      logger.info('Themeable widgets:');
      for (final entry in resolved.entries) {
        final targetCount = entry.targets.length;
        final suffix = targetCount == 1 ? 'target' : 'targets';
        logger.info('  - ${entry.componentId} ($targetCount $suffix)');
      }
    } catch (error) {
      logger.warn('Failed to load widget theme manifest: $error');
    }
  }

  Future<void> listWidgetThemeTargets(
    String componentId, {
    bool refresh = false,
  }) async {
    try {
      final resolved = await _resolveWidgetThemeRegistry(refresh: refresh);
      if (resolved == null) {
        logger.info('This registry does not provide widget theme metadata.');
        return;
      }
      final entry = _findWidgetThemeEntry(componentId, resolved.entries);
      if (entry == null) {
        logger.warn('Widget "$componentId" is not themeable in this registry.');
        return;
      }
      if (entry.targets.isEmpty) {
        logger.info(
            'No widget theme targets available for ${entry.componentId}.');
        return;
      }
      logger.info('Theme targets for ${entry.componentId}:');
      for (final target in entry.targets) {
        final marker = target.isDefault ||
                (entry.defaultTarget != null &&
                    entry.defaultTarget == target.id)
            ? ' (default)'
            : '';
        logger.info('  - ${target.id}$marker');
      }
    } catch (error) {
      logger.warn('Failed to load widget theme targets: $error');
    }
  }

  Future<void> applyThemeById(String identifier, {bool refresh = false}) async {
    final presets = await _loadResolvedThemePresets(refresh: refresh);
    if (presets.isEmpty) {
      logger.info('No theme presets available.');
      return;
    }
    final preset = _findPreset(identifier, presets);
    if (preset == null) {
      logger.warn(
        'Theme "$identifier" not found. Use "--list" to view available presets.',
      );
      return;
    }
    await _applyThemePreset(preset);
  }

  Future<void> applyThemeFromFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      logger.warn('Theme file not found: $filePath');
      return;
    }
    try {
      final content = await file.readAsString();
      final data = jsonDecode(content);
      if (data is! Map<String, dynamic>) {
        logger.warn('Theme file must contain a JSON object.');
        return;
      }
      await applyThemeFromJson(data, sourceLabel: filePath);
    } catch (e) {
      logger.warn('Failed to read theme file: $e');
    }
  }

  Future<void> applyThemeFromUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      logger.warn('Theme URL must be a valid http/https URL.');
      return;
    }
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        logger
            .warn('Failed to fetch theme URL (status ${response.statusCode}).');
        return;
      }
      final content = await response.transform(utf8.decoder).join();
      final data = jsonDecode(content);
      if (data is! Map<String, dynamic>) {
        logger.warn('Theme URL must return a JSON object.');
        return;
      }
      await applyThemeFromJson(data, sourceLabel: url);
    } catch (e) {
      logger.warn('Failed to fetch theme URL: $e');
    } finally {
      client.close();
    }
  }

  Future<void> applyWidgetThemeFromFile(
    String componentId,
    String filePath, {
    bool refresh = false,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      logger.warn('Widget theme file not found: $filePath');
      return;
    }
    await _applyWidgetTheme(
      componentId,
      action: 'apply',
      source: {
        'type': 'file',
        'path': p.normalize(file.absolute.path),
      },
      refresh: refresh,
    );
  }

  Future<void> applyWidgetThemeFromUrl(
    String componentId,
    String url, {
    bool refresh = false,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      logger.warn('Widget theme URL must be a valid http/https URL.');
      return;
    }
    await _applyWidgetTheme(
      componentId,
      action: 'apply',
      source: {
        'type': 'url',
        'url': url,
      },
      refresh: refresh,
    );
  }

  Future<void> resetWidgetTheme(
    String componentId, {
    bool refresh = false,
  }) async {
    await _applyWidgetTheme(
      componentId,
      action: 'reset',
      source: null,
      refresh: refresh,
    );
  }

  Future<void> applyThemeFromJson(
    Map<String, dynamic> data, {
    String? sourceLabel,
  }) async {
    final idRaw = data['id']?.toString().trim();
    final nameRaw = data['name']?.toString().trim();
    final id = (idRaw == null || idRaw.isEmpty) ? 'custom' : idRaw;
    final name = (nameRaw == null || nameRaw.isEmpty) ? 'Custom' : nameRaw;
    final light = _parseThemeColors(data['light'], 'light');
    final dark = _parseThemeColors(data['dark'], 'dark');
    if (light == null || dark == null) {
      logger.warn('Theme JSON must include "light" and "dark" color maps.');
      return;
    }
    final preset = RegistryThemePresetData(
      id: id,
      name: name,
      light: light,
      dark: dark,
    );
    await _applyThemePreset(preset);
    if (sourceLabel != null && sourceLabel.isNotEmpty) {
      logger.detail('Applied custom theme from: $sourceLabel');
    }
  }

  Map<String, String>? _parseThemeColors(Object? raw, String label) {
    if (raw is! Map) {
      logger.warn('Theme "$label" must be an object of key/value colors.');
      return null;
    }
    final result = <String, String>{};
    raw.forEach((key, value) {
      if (key == null) {
        return;
      }
      final name = key.toString();
      if (name.isEmpty || value == null) {
        return;
      }
      result[name] = value.toString();
    });
    if (result.isEmpty) {
      logger.warn('Theme "$label" contains no color entries.');
      return null;
    }
    return result;
  }

  Future<void> _interactiveThemeSelection({
    required bool skipIfConfigured,
    bool refresh = false,
  }) async {
    final presets = await _loadResolvedThemePresets(refresh: refresh);
    if (presets.isEmpty) {
      return;
    }
    if (skipIfConfigured) {
      final config = await ShadcnConfig.load(targetDir);
      if (config.themeId != null && config.themeId!.isNotEmpty) {
        return;
      }
    }
    final config = await ShadcnConfig.load(targetDir);
    logger.info('Select a starter theme (press Enter to skip):');
    for (var i = 0; i < presets.length; i++) {
      final preset = presets[i];
      final isCurrent = preset.id == config.themeId;
      final suffix = isCurrent ? ' (current)' : '';
      logger.info('  ${i + 1}) ${preset.name} (${preset.id})$suffix');
    }
    stdout.write('Theme number: ');
    final input = stdin.readLineSync();
    if (input == null || input.trim().isEmpty) {
      logger.info('Skipping theme selection.');
      return;
    }
    final trimmed = input.trim();
    RegistryThemePresetData? chosen;
    final index = int.tryParse(trimmed);
    if (index != null && index >= 1 && index <= presets.length) {
      chosen = presets[index - 1];
    } else {
      chosen = _findPreset(trimmed, presets);
    }
    if (chosen == null) {
      logger.warn('Invalid selection. Skipping theme selection.');
      return;
    }
    await _applyThemePreset(chosen);
  }

  Future<List<RegistryThemePresetData>> _loadResolvedThemePresets({
    bool refresh = false,
  }) async {
    await _ensureConfigLoaded();
    final config = _cachedConfig ?? const ShadcnConfig();
    final entry = config.registryConfig(registryNamespace);
    final themesPath = themesPathOverride ?? entry?.themesPath;

    if (themesPath == null || themesPath.trim().isEmpty) {
      return loadThemePresets(logger: logger);
    }

    final registryBaseUrl = registryBaseUrlOverride ??
        entry?.baseUrl ??
        entry?.registryUrl ??
        registry.sourceRoot.root;
    final registryId = _themeRegistryId(registryBaseUrl);
    final indexLoader = ThemeIndexLoader(
      registryId: registryId,
      registryBaseUrl: registryBaseUrl,
      themesPath: themesPath,
      themesSchemaPath: themesSchemaPathOverride ?? entry?.themesSchemaPath,
      refresh: refresh,
      offline: registry.sourceRoot.offline,
      logger: logger,
      cacheRootPath: _themeCacheRootPath(registryId),
    );
    final presetLoader = ThemePresetLoader(
      registryId: registryId,
      registryBaseUrl: registryBaseUrl,
      themesPath: themesPath,
      themesSchemaPath: themesSchemaPathOverride ?? entry?.themesSchemaPath,
      themeConverterDartPath:
          themeConverterDartPathOverride ?? entry?.themeConverterDartPath,
      refresh: refresh,
      offline: registry.sourceRoot.offline,
      logger: logger,
      cacheRootPath: _themeCacheRootPath(registryId),
    );
    return loadThemePresets(
      themeIndexLoader: indexLoader,
      themePresetLoader: presetLoader,
      logger: logger,
    );
  }

  Future<void> _applyWidgetTheme(
    String componentId, {
    required String action,
    required Map<String, dynamic>? source,
    bool refresh = false,
  }) async {
    try {
      final resolved = await _resolveWidgetThemeRegistry(refresh: refresh);
      if (resolved == null) {
        logger.info('This registry does not provide widget themes.');
        return;
      }
      final entry = _findWidgetThemeEntry(componentId, resolved.entries);
      if (entry == null) {
        logger.warn('Widget "$componentId" is not themeable in this registry.');
        return;
      }
      if (resolved.themeConverterDartPath == null ||
          resolved.themeConverterDartPath!.trim().isEmpty) {
        logger.warn('This registry does not provide a theme converter script.');
        return;
      }

      final converter = RegistryThemeConverterClient(
        registryId: resolved.registryId,
        registryBaseUrl: resolved.registryBaseUrl,
        converterPath: resolved.themeConverterDartPath!,
        offline: registry.sourceRoot.offline,
        logger: logger,
        cacheRootPath: resolved.cacheRootPath,
      );
      final config = _cachedConfig ?? const ShadcnConfig();
      final request = <String, dynamic>{
        'scope': 'widget',
        'action': action,
        'namespace': resolved.namespace,
        'componentId': entry.componentId,
        'source': source,
        'context': {
          'targetDir': targetDir,
          'registryRoot': registry.registryRoot.root,
          'registrySourceRoot': registry.sourceRoot.root,
          'installPath': _installPath(config),
          'sharedPath': _sharedPath(config),
          'widgetThemesPath': resolved.widgetThemesPath,
        },
      };
      final response = await converter.execute(request);
      if (response.operations.isEmpty) {
        logger.info(
          action == 'reset'
              ? 'No widget theme overrides to reset for ${entry.componentId}.'
              : 'No widget theme changes were generated for ${entry.componentId}.',
        );
        return;
      }
      await _applyThemeInstallPlan(response.operations);
      final resolvedTarget = response.resolvedTargetThemeType;
      final targetSuffix = resolvedTarget == null || resolvedTarget.isEmpty
          ? ''
          : ' [$resolvedTarget]';
      if (action == 'reset') {
        logger.success('Reset widget theme: ${entry.componentId}$targetSuffix');
      } else {
        logger
            .success('Applied widget theme: ${entry.componentId}$targetSuffix');
      }
    } catch (error) {
      logger.warn('Failed to $action widget theme: $error');
    }
  }

  String _themeRegistryId(String registryBaseUrl) {
    final safe = registryBaseUrl.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safe.length <= 80) {
      return safe;
    }
    return safe.substring(0, 80);
  }

  Future<_ResolvedWidgetThemeRegistry?> _resolveWidgetThemeRegistry({
    bool refresh = false,
  }) async {
    await _ensureConfigLoaded();
    final config = _cachedConfig ?? const ShadcnConfig();
    final entry = config.registryConfig(registryNamespace);
    final widgetThemesPath =
        (widgetThemesPathOverride ?? entry?.widgetThemesPath)?.trim();
    if (widgetThemesPath == null || widgetThemesPath.isEmpty) {
      return null;
    }
    final registryBaseUrl = registryBaseUrlOverride ??
        entry?.baseUrl ??
        entry?.registryUrl ??
        registry.sourceRoot.root;
    final registryId = _themeRegistryId(registryBaseUrl);
    final loader = WidgetThemeIndexLoader(
      registryId: registryId,
      registryBaseUrl: registryBaseUrl,
      widgetThemesPath: widgetThemesPath,
      refresh: refresh,
      offline: registry.sourceRoot.offline,
      logger: logger,
      cacheRootPath: _themeCacheRootPath(registryId),
    );
    final data = await loader.load();
    return _ResolvedWidgetThemeRegistry(
      namespace: registryNamespace ?? config.effectiveDefaultNamespace,
      registryId: registryId,
      registryBaseUrl: registryBaseUrl,
      widgetThemesPath: widgetThemesPath,
      themeConverterDartPath:
          themeConverterDartPathOverride ?? entry?.themeConverterDartPath,
      cacheRootPath: _themeCacheRootPath(registryId),
      entries: loader.entriesFrom(data),
    );
  }

  String _themeCacheRootPath(String registryId) {
    return p.join(targetDir, '.shadcn', 'cache', 'registry', registryId);
  }

  WidgetThemeIndexEntry? _findWidgetThemeEntry(
    String componentId,
    List<WidgetThemeIndexEntry> entries,
  ) {
    final normalized = componentId.trim().toLowerCase();
    for (final entry in entries) {
      if (entry.componentId.toLowerCase() == normalized) {
        return entry;
      }
    }
    return null;
  }

  Future<void> _applyThemeInstallPlan(
    List<RegistryThemeInstallOperation> operations,
  ) async {
    final projectRoot = p.normalize(targetDir);
    final sorted = [...operations]
      ..sort((left, right) => left.path.compareTo(right.path));
    for (final operation in sorted) {
      final file = _resolvePlanFile(operation.path, projectRoot);
      switch (operation.type) {
        case 'write_file':
          final content = operation.content;
          if (content == null) {
            throw Exception(
                'write_file requires content for ${operation.path}');
          }
          await _atomicWriteFile(file, content);
          break;
        case 'patch_file':
          final find = operation.find;
          final replace = operation.replace;
          if (find == null || replace == null) {
            throw Exception(
              'patch_file requires find/replace for ${operation.path}',
            );
          }
          if (!file.existsSync()) {
            throw Exception('Patch target not found: ${operation.path}');
          }
          final current = await file.readAsString();
          if (!current.contains(find)) {
            throw Exception(
              'Patch anchor not found in ${operation.path}: ${operation.find}',
            );
          }
          final updated = operation.replaceAll
              ? current.replaceAll(find, replace)
              : current.replaceFirst(find, replace);
          await _atomicWriteFile(file, updated);
          break;
        case 'ensure_import':
          final importStatement = operation.importStatement;
          if (importStatement == null || importStatement.trim().isEmpty) {
            throw Exception(
              'ensure_import requires import for ${operation.path}',
            );
          }
          if (!file.existsSync()) {
            throw Exception('Import target not found: ${operation.path}');
          }
          final current = await file.readAsString();
          if (current.contains(importStatement)) {
            break;
          }
          final updated = _insertImport(current, importStatement);
          await _atomicWriteFile(file, updated);
          break;
        case 'delete_file':
          if (file.existsSync()) {
            await file.delete();
          }
          break;
        default:
          throw Exception('Unsupported install operation: ${operation.type}');
      }
    }
  }

  File _resolvePlanFile(String relativePath, String projectRoot) {
    final normalized = p.normalize(relativePath);
    if (p.isAbsolute(normalized)) {
      throw Exception('Install plan path must be relative: $relativePath');
    }
    if (normalized == '..' ||
        normalized.startsWith('../') ||
        normalized.startsWith('..\\')) {
      throw Exception('Install plan path escapes project root: $relativePath');
    }
    final resolved = File(p.join(projectRoot, normalized));
    final normalizedResolved = p.normalize(resolved.path);
    if (!(normalizedResolved == projectRoot ||
        normalizedResolved.startsWith('$projectRoot${p.separator}'))) {
      throw Exception('Install plan path escapes project root: $relativePath');
    }
    return resolved;
  }

  Future<void> _atomicWriteFile(File file, String content) async {
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    final tempFile = File('${file.path}.tmp');
    await tempFile.writeAsString(content, flush: true);
    if (file.existsSync()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
  }

  String _insertImport(String content, String importStatement) {
    final normalizedImport = importStatement.trim().endsWith(';')
        ? importStatement.trim()
        : '${importStatement.trim()};';
    final lines = content.split('\n');
    var lastImportIndex = -1;
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].trimLeft().startsWith('import ')) {
        lastImportIndex = index;
      }
    }
    if (lastImportIndex == -1) {
      return '$normalizedImport\n$content';
    }
    lines.insert(lastImportIndex + 1, normalizedImport);
    return lines.join('\n');
  }

  Future<void> _applyThemePreset(RegistryThemePresetData preset) async {
    await _ensureConfigLoaded();
    final themeFilePath = _resolveColorSchemeFilePath();
    if (themeFilePath == null) {
      logger.warn('Theme file not found. Run "flutter_shadcn init" first.');
      return;
    }
    final themeFile = File(themeFilePath);
    await applyPresetToColorScheme(filePath: themeFile.path, preset: preset);
    final config = await ShadcnConfig.load(targetDir);
    await ShadcnConfig.save(targetDir, config.copyWith(themeId: preset.id));
    logger.success('Applied theme: ${preset.name}');
  }

  RegistryThemePresetData? _findPreset(
    String identifier,
    List<RegistryThemePresetData> presets,
  ) {
    final normalized = identifier.toLowerCase();
    for (final preset in presets) {
      if (preset.id.toLowerCase() == normalized ||
          preset.name.toLowerCase() == normalized) {
        return preset;
      }
    }
    return null;
  }

  String? _resolveColorSchemeFilePath() {
    final sharedPath = _sharedPath(_cachedConfig);
    final candidates = <String>[
      p.join(targetDir, sharedPath, 'theme', 'color_scheme.dart'),
      p.join(targetDir, sharedPath, 'theme', '_impl', 'core',
          'color_schemes.dart'),
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }
}

class _ResolvedWidgetThemeRegistry {
  final String namespace;
  final String registryId;
  final String registryBaseUrl;
  final String widgetThemesPath;
  final String? themeConverterDartPath;
  final String cacheRootPath;
  final List<WidgetThemeIndexEntry> entries;

  const _ResolvedWidgetThemeRegistry({
    required this.namespace,
    required this.registryId,
    required this.registryBaseUrl,
    required this.widgetThemesPath,
    required this.themeConverterDartPath,
    required this.cacheRootPath,
    required this.entries,
  });
}
