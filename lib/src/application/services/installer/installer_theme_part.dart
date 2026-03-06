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
    final response = await _runWidgetThemeConverter(
      action: 'list',
      refresh: refresh,
    );
    if (response == null) {
      return;
    }
    _printConverterPreview(response.preview);
    _logConverterMessages(response.messages);
  }

  Future<void> listWidgetThemeTargets(
    String componentId, {
    bool refresh = false,
  }) async {
    final response = await _runWidgetThemeConverter(
      action: 'list-targets',
      componentId: componentId,
      refresh: refresh,
    );
    if (response == null) {
      return;
    }
    _printConverterPreview(response.preview);
    _logConverterMessages(response.messages);
  }

  Future<void> applyThemeById(String identifier, {bool refresh = false}) async {
    final resolved = await _resolveThemeRegistry(refresh: refresh);
    if (resolved == null) {
      logger.info('This registry does not provide theme presets.');
      return;
    }
    final entry = _findThemeIndexEntry(identifier, resolved.indexEntries);
    if (entry == null) {
      logger.warn(
        'Theme "$identifier" not found. Use "--list" to view available presets.',
      );
      return;
    }
    final presetLoader = _buildThemePresetLoader(resolved, refresh: refresh);
    final payloadFile = await presetLoader.cachePresetJson(entry);
    final response = await _runThemeConverter(
      registryId: resolved.registryId,
      registryBaseUrl: resolved.registryBaseUrl,
      themeConverterDartPath: resolved.themeConverterDartPath ?? '',
      cacheRootPath: resolved.cacheRootPath,
      request: <String, dynamic>{
        'scope': 'global',
        'action': 'apply',
        'namespace': resolved.namespace,
        'themeId': entry.id,
        'payloadFile': p.normalize(payloadFile.path),
        'context': _converterContext(),
      },
    );
    await _applyThemeConverterResult(
      response,
      successMessage: 'Applied theme: ${entry.name}',
      themeId: entry.id,
    );
  }

  Future<void> applyThemeFromFile(String filePath) async {
    if (await _resolveThemeConverterRegistry() == null) {
      logger.info('This registry does not provide theme installation support.');
      return;
    }
    final data = await _readJsonObjectFile(filePath, label: 'Theme file');
    if (data == null) {
      return;
    }
    await applyThemeFromJson(
      data,
      sourceLabel: filePath,
    );
  }

  Future<void> applyThemeFromUrl(String url) async {
    if (await _resolveThemeConverterRegistry() == null) {
      logger.info('This registry does not provide theme installation support.');
      return;
    }
    final data = await _fetchJsonObjectFromUrl(url, label: 'Theme URL');
    if (data == null) {
      return;
    }
    await applyThemeFromJson(
      data,
      sourceLabel: url,
    );
  }

  Future<void> applyWidgetThemeFromFile(
    String componentId,
    String filePath, {
    bool refresh = false,
  }) async {
    final converterRegistry = await _resolveThemeConverterRegistry();
    if (converterRegistry == null) {
      logger.info('This registry does not provide widget theming support.');
      return;
    }
    final data =
        await _readJsonObjectFile(filePath, label: 'Widget theme file');
    if (data == null) {
      return;
    }
    final payloadFile = await _writeWidgetPayloadCache(
      namespace: converterRegistry.namespace,
      componentId: componentId,
      data: data,
      sourceHint: p.basename(filePath),
    );
    final response = await _runThemeConverter(
      registryId: converterRegistry.registryId,
      registryBaseUrl: converterRegistry.registryBaseUrl,
      themeConverterDartPath: converterRegistry.themeConverterDartPath,
      cacheRootPath: converterRegistry.cacheRootPath,
      request: <String, dynamic>{
        'scope': 'widget',
        'action': 'apply',
        'namespace': converterRegistry.namespace,
        'componentId': componentId.trim(),
        'payloadFile': p.normalize(payloadFile.path),
        'context': _converterContext(),
      },
    );
    await _applyThemeConverterResult(
      response,
      successMessage: _widgetSuccessMessage(
        action: 'apply',
        componentId: componentId,
        response: response,
      ),
    );
  }

  Future<void> applyWidgetThemeFromUrl(
    String componentId,
    String url, {
    bool refresh = false,
  }) async {
    final converterRegistry = await _resolveThemeConverterRegistry();
    if (converterRegistry == null) {
      logger.info('This registry does not provide widget theming support.');
      return;
    }
    final data = await _fetchJsonObjectFromUrl(url, label: 'Widget theme URL');
    if (data == null) {
      return;
    }
    final payloadFile = await _writeWidgetPayloadCache(
      namespace: converterRegistry.namespace,
      componentId: componentId,
      data: data,
      sourceHint: _urlFileHint(url, fallback: 'widget-theme.json'),
    );
    final response = await _runThemeConverter(
      registryId: converterRegistry.registryId,
      registryBaseUrl: converterRegistry.registryBaseUrl,
      themeConverterDartPath: converterRegistry.themeConverterDartPath,
      cacheRootPath: converterRegistry.cacheRootPath,
      request: <String, dynamic>{
        'scope': 'widget',
        'action': 'apply',
        'namespace': converterRegistry.namespace,
        'componentId': componentId.trim(),
        'payloadFile': p.normalize(payloadFile.path),
        'context': _converterContext(),
      },
    );
    await _applyThemeConverterResult(
      response,
      successMessage: _widgetSuccessMessage(
        action: 'apply',
        componentId: componentId,
        response: response,
      ),
    );
  }

  Future<void> resetWidgetTheme(
    String componentId, {
    bool refresh = false,
  }) async {
    final response = await _runWidgetThemeConverter(
      action: 'reset',
      componentId: componentId,
      refresh: refresh,
    );
    if (response == null) {
      return;
    }
    await _applyThemeConverterResult(
      response,
      successMessage: _widgetSuccessMessage(
        action: 'reset',
        componentId: componentId,
        response: response,
      ),
      emptyMessage: 'No widget theme overrides to reset for $componentId.',
    );
  }

  Future<void> applyThemeFromJson(
    Map<String, dynamic> data, {
    String? sourceLabel,
  }) async {
    final resolvedConverter = await _resolveThemeConverterRegistry();
    if (resolvedConverter == null) {
      logger.info('This registry does not provide theme installation support.');
      return;
    }
    final payloadFile = await _writeThemePayloadCache(
      namespace: resolvedConverter.namespace,
      data: data,
      sourceHint: sourceLabel,
    );
    final response = await _runThemeConverter(
      registryId: resolvedConverter.registryId,
      registryBaseUrl: resolvedConverter.registryBaseUrl,
      themeConverterDartPath: resolvedConverter.themeConverterDartPath,
      cacheRootPath: resolvedConverter.cacheRootPath,
      request: <String, dynamic>{
        'scope': 'global',
        'action': 'apply',
        'namespace': resolvedConverter.namespace,
        'themeId': _themeIdFromPayload(data),
        'payloadFile': p.normalize(payloadFile.path),
        'context': _converterContext(),
      },
    );
    await _applyThemeConverterResult(
      response,
      successMessage: 'Applied theme: ${_themeNameFromPayload(data)}',
      themeId: _themeIdFromPayload(data),
    );
    if (sourceLabel != null && sourceLabel.isNotEmpty) {
      logger.detail('Applied theme payload from: $sourceLabel');
    }
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
    await applyThemeById(chosen.id, refresh: refresh);
  }

  Future<List<RegistryThemePresetData>> _loadResolvedThemePresets({
    bool refresh = false,
  }) async {
    final resolved = await _resolveThemeRegistry(refresh: refresh);
    if (resolved == null) {
      return const <RegistryThemePresetData>[];
    }
    final presetLoader = _buildThemePresetLoader(resolved, refresh: refresh);
    return loadThemePresets(
      themeIndexLoader: resolved.indexLoader,
      themePresetLoader: presetLoader,
      logger: logger,
    );
  }

  Future<_ResolvedThemeRegistry?> _resolveThemeRegistry({
    required bool refresh,
  }) async {
    await _ensureConfigLoaded();
    final config = _cachedConfig ?? const ShadcnConfig();
    final entry = config.registryConfig(registryNamespace);
    final themesPath = themesPathOverride ?? entry?.themesPath;
    if (themesPath == null || themesPath.trim().isEmpty) {
      return null;
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
    final indexData = await indexLoader.load();
    final entries = indexLoader.entriesFrom(indexData);
    return _ResolvedThemeRegistry(
      namespace: registryNamespace ?? config.effectiveDefaultNamespace,
      registryId: registryId,
      registryBaseUrl: registryBaseUrl,
      themesPath: themesPath,
      themesSchemaPath: themesSchemaPathOverride ?? entry?.themesSchemaPath,
      themeConverterDartPath:
          themeConverterDartPathOverride ?? entry?.themeConverterDartPath,
      cacheRootPath: _themeCacheRootPath(registryId),
      indexLoader: indexLoader,
      indexEntries: entries,
    );
  }

  Future<_ResolvedThemeConverterRegistry?>
      _resolveThemeConverterRegistry() async {
    await _ensureConfigLoaded();
    final config = _cachedConfig ?? const ShadcnConfig();
    final entry = config.registryConfig(registryNamespace);
    final converterPath =
        themeConverterDartPathOverride ?? entry?.themeConverterDartPath;
    if (converterPath == null || converterPath.trim().isEmpty) {
      return null;
    }
    final registryBaseUrl = registryBaseUrlOverride ??
        entry?.baseUrl ??
        entry?.registryUrl ??
        registry.sourceRoot.root;
    final registryId = _themeRegistryId(registryBaseUrl);
    return _ResolvedThemeConverterRegistry(
      namespace: registryNamespace ?? config.effectiveDefaultNamespace,
      registryId: registryId,
      registryBaseUrl: registryBaseUrl,
      themeConverterDartPath: converterPath,
      cacheRootPath: _themeCacheRootPath(registryId),
    );
  }

  ThemePresetLoader _buildThemePresetLoader(
    _ResolvedThemeRegistry resolved, {
    required bool refresh,
  }) {
    return ThemePresetLoader(
      registryId: resolved.registryId,
      registryBaseUrl: resolved.registryBaseUrl,
      themesPath: resolved.themesPath,
      themesSchemaPath: resolved.themesSchemaPath,
      themeConverterDartPath: resolved.themeConverterDartPath,
      refresh: refresh,
      offline: registry.sourceRoot.offline,
      logger: logger,
      cacheRootPath: resolved.cacheRootPath,
    );
  }

  Future<RegistryThemeConverterResponse?> _runWidgetThemeConverter({
    required String action,
    String? componentId,
    File? payloadFile,
    required bool refresh,
  }) async {
    final resolved = await _resolveThemeConverterRegistry();
    if (resolved == null) {
      logger.info('This registry does not provide widget theming support.');
      return null;
    }
    final request = <String, dynamic>{
      'scope': 'widget',
      'action': action,
      'namespace': resolved.namespace,
      if (componentId != null && componentId.trim().isNotEmpty)
        'componentId': componentId.trim(),
      if (payloadFile != null) 'payloadFile': p.normalize(payloadFile.path),
      'context': _converterContext(),
    };
    return _runThemeConverter(
      registryId: resolved.registryId,
      registryBaseUrl: resolved.registryBaseUrl,
      themeConverterDartPath: resolved.themeConverterDartPath,
      cacheRootPath: resolved.cacheRootPath,
      request: request,
    );
  }

  Future<RegistryThemeConverterResponse> _runThemeConverter({
    required String registryId,
    required String registryBaseUrl,
    required String themeConverterDartPath,
    required String cacheRootPath,
    required Map<String, dynamic> request,
  }) async {
    if (themeConverterDartPath.trim().isEmpty) {
      throw Exception(
          'This registry does not provide a theme converter script.');
    }
    final converter = RegistryThemeConverterClient(
      registryId: registryId,
      registryBaseUrl: registryBaseUrl,
      converterPath: themeConverterDartPath,
      offline: registry.sourceRoot.offline,
      logger: logger,
      cacheRootPath: cacheRootPath,
    );
    return converter.execute(request);
  }

  Map<String, dynamic> _converterContext() {
    return <String, dynamic>{
      'targetDir': targetDir,
      'registryRoot': registry.registryRoot.root,
      'registrySourceRoot': registry.sourceRoot.root,
      'installPath': _installPath(_cachedConfig),
      'sharedPath': _sharedPath(_cachedConfig),
    };
  }

  Future<void> _applyThemeConverterResult(
    RegistryThemeConverterResponse response, {
    required String successMessage,
    String? emptyMessage,
    String? themeId,
  }) async {
    if (response.operations.isNotEmpty) {
      await _applyThemeInstallPlan(response.operations);
    } else if (emptyMessage != null) {
      logger.info(emptyMessage);
    }
    _printConverterPreview(response.preview);
    _logConverterMessages(response.messages);
    if (themeId != null && themeId.isNotEmpty) {
      final config = await ShadcnConfig.load(targetDir);
      await ShadcnConfig.save(targetDir, config.copyWith(themeId: themeId));
    }
    if (response.operations.isNotEmpty) {
      logger.success(successMessage);
    }
  }

  void _printConverterPreview(Map<String, dynamic>? preview) {
    if (preview == null || preview.isEmpty) {
      return;
    }
    final components = preview['components'];
    if (components is List) {
      if (components.isEmpty) {
        logger.info('No themeable widgets available.');
        return;
      }
      logger.info('Themeable widgets:');
      for (final item in components) {
        if (item is! Map) {
          continue;
        }
        final componentId = item['componentId']?.toString() ?? '';
        final targets = item['targets'];
        final targetCount = targets is List ? targets.length : 0;
        final suffix = targetCount == 1 ? 'target' : 'targets';
        logger.info('  - $componentId ($targetCount $suffix)');
      }
      return;
    }
    final targets = preview['targets'];
    if (targets is List) {
      if (targets.isEmpty) {
        logger.info('No widget theme targets available.');
        return;
      }
      final componentId = preview['componentId']?.toString();
      if (componentId != null && componentId.isNotEmpty) {
        logger.info('Theme targets for $componentId:');
      }
      for (final item in targets) {
        if (item is! Map) {
          continue;
        }
        final id = item['id']?.toString() ?? '';
        final isDefault = item['default'] == true;
        final marker = isDefault ? ' (default)' : '';
        logger.info('  - $id$marker');
      }
    }
  }

  void _logConverterMessages(List<RegistryThemeConverterMessage> messages) {
    for (final message in messages) {
      switch (message.level) {
        case 'success':
          logger.success(message.text);
          break;
        case 'warn':
        case 'warning':
          logger.warn(message.text);
          break;
        case 'detail':
          logger.detail(message.text);
          break;
        default:
          logger.info(message.text);
          break;
      }
    }
  }

  Future<Map<String, dynamic>?> _readJsonObjectFile(
    String filePath, {
    required String label,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      logger.warn('$label not found: $filePath');
      return null;
    }
    try {
      final content = await file.readAsString();
      final data = jsonDecode(content);
      if (data is! Map<String, dynamic>) {
        logger.warn('$label must contain a JSON object.');
        return null;
      }
      return data;
    } catch (error) {
      logger.warn('Failed to read $label: $error');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchJsonObjectFromUrl(
    String url, {
    required String label,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      logger.warn('$label must be a valid http/https URL.');
      return null;
    }
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        logger.warn('Failed to fetch $label (status ${response.statusCode}).');
        return null;
      }
      final content = await response.transform(utf8.decoder).join();
      final data = jsonDecode(content);
      if (data is! Map<String, dynamic>) {
        logger.warn('$label must return a JSON object.');
        return null;
      }
      return data;
    } catch (error) {
      logger.warn('Failed to fetch $label: $error');
      return null;
    } finally {
      client.close();
    }
  }

  Future<File> _writeThemePayloadCache({
    required String namespace,
    required Map<String, dynamic> data,
    String? sourceHint,
  }) async {
    final fileName = _safeFileName(
      _themeIdFromPayload(data).isNotEmpty
          ? '${_themeIdFromPayload(data)}.json'
          : (sourceHint == null || sourceHint.isEmpty
              ? 'custom-theme.json'
              : sourceHint),
    );
    final file = File(
      p.join(
        targetDir,
        '.shadcn',
        'cache',
        'themes',
        namespace,
        fileName,
      ),
    );
    return _writeCachedJsonFile(file, data);
  }

  Future<File> _writeWidgetPayloadCache({
    required String namespace,
    required String componentId,
    required Map<String, dynamic> data,
    required String sourceHint,
  }) async {
    final file = File(
      p.join(
        targetDir,
        '.shadcn',
        'cache',
        'widget_themes',
        namespace,
        componentId.trim().toLowerCase(),
        _safeFileName(sourceHint.isEmpty ? 'widget-theme.json' : sourceHint),
      ),
    );
    return _writeCachedJsonFile(file, data);
  }

  Future<File> _writeCachedJsonFile(
    File file,
    Map<String, dynamic> data,
  ) async {
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(data)}\n', flush: true);
    return file;
  }

  String _safeFileName(String raw) {
    final trimmed = raw.trim();
    final base = trimmed.isEmpty ? 'payload.json' : trimmed;
    final sanitized = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return sanitized.endsWith('.json') ? sanitized : '$sanitized.json';
  }

  String _urlFileHint(String url, {required String fallback}) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return fallback;
    }
    final segment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    return segment.trim().isEmpty ? fallback : segment;
  }

  String _themeRegistryId(String registryBaseUrl) {
    final safe = registryBaseUrl.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safe.length <= 80) {
      return safe;
    }
    return safe.substring(0, 80);
  }

  String _themeCacheRootPath(String registryId) {
    return p.join(targetDir, '.shadcn', 'cache', 'registry', registryId);
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

  ThemeIndexEntry? _findThemeIndexEntry(
    String identifier,
    List<ThemeIndexEntry> entries,
  ) {
    final normalized = identifier.trim().toLowerCase();
    for (final entry in entries) {
      if (entry.id.toLowerCase() == normalized ||
          entry.name.toLowerCase() == normalized) {
        return entry;
      }
    }
    return null;
  }

  String? _resolveColorSchemeFilePath() {
    final sharedPath = _sharedPath(_cachedConfig);
    final candidates = <String>[
      p.join(targetDir, sharedPath, 'theme', 'color_scheme.dart'),
      p.join(
        targetDir,
        sharedPath,
        'theme',
        '_impl',
        'core',
        'color_schemes.dart',
      ),
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

  String _themeIdFromPayload(Map<String, dynamic> data) {
    final id = data['id']?.toString().trim();
    if (id != null && id.isNotEmpty) {
      return id;
    }
    return 'custom';
  }

  String _themeNameFromPayload(Map<String, dynamic> data) {
    final name = data['name']?.toString().trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return _themeIdFromPayload(data);
  }

  String _widgetSuccessMessage({
    required String action,
    required String componentId,
    required RegistryThemeConverterResponse response,
  }) {
    final resolvedComponent = response.resolvedComponent;
    final resolvedTarget = response.resolvedTargetThemeType;
    final componentLabel =
        (resolvedComponent == null || resolvedComponent.isEmpty)
            ? componentId
            : resolvedComponent;
    final targetSuffix = (resolvedTarget == null || resolvedTarget.isEmpty)
        ? ''
        : ' [$resolvedTarget]';
    if (action == 'reset') {
      return 'Reset widget theme: $componentLabel$targetSuffix';
    }
    return 'Applied widget theme: $componentLabel$targetSuffix';
  }
}

class _ResolvedThemeRegistry {
  final String namespace;
  final String registryId;
  final String registryBaseUrl;
  final String themesPath;
  final String? themesSchemaPath;
  final String? themeConverterDartPath;
  final String cacheRootPath;
  final ThemeIndexLoader indexLoader;
  final List<ThemeIndexEntry> indexEntries;

  const _ResolvedThemeRegistry({
    required this.namespace,
    required this.registryId,
    required this.registryBaseUrl,
    required this.themesPath,
    required this.themesSchemaPath,
    required this.themeConverterDartPath,
    required this.cacheRootPath,
    required this.indexLoader,
    required this.indexEntries,
  });
}

class _ResolvedThemeConverterRegistry {
  const _ResolvedThemeConverterRegistry({
    required this.namespace,
    required this.registryId,
    required this.registryBaseUrl,
    required this.themeConverterDartPath,
    required this.cacheRootPath,
  });

  final String namespace;
  final String registryId;
  final String registryBaseUrl;
  final String themeConverterDartPath;
  final String cacheRootPath;
}
