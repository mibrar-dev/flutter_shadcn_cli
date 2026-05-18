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
    final entries = await _loadResolvedThemeEntries(refresh: refresh);
    if (entries.isEmpty) {
      logger.info('No theme presets available.');
      return;
    }
    final config = await ShadcnConfig.load(targetDir);
    final currentTheme = config.themeId;
    logger.info('Installed theme presets:');
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final marker = entry.id == currentTheme ? ' (current)' : '';
      logger.info('  ${i + 1}) ${entry.name} (${entry.id})$marker');
    }
  }

  Future<void> listWidgetThemes({bool refresh = false}) async {
    throw _unsupportedWidgetThemeFlow(
      action:
          'Widget theme listing is not supported in the declarative manifest flow yet.',
    );
  }

  Future<void> listWidgetThemeTargets(
    String componentId, {
    bool refresh = false,
  }) async {
    throw _unsupportedWidgetThemeFlow(
      action:
          'Widget theme target inspection is not supported in the declarative manifest flow yet.',
    );
  }

  Future<void> applyThemeById(String identifier, {bool refresh = false}) async {
    logger.progress('Resolving theme preset: $identifier');
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
    logger.progress('Loading theme manifest for ${entry.name}');
    final manifest = await _loadThemeArtifactManifestById(
      resolved: resolved,
      entry: entry,
    );
    await _applyThemeArtifactManifest(
      manifest,
      registryId: resolved.registryId,
      registryBaseUrl: resolved.registryBaseUrl,
      successMessage: 'Applied theme: ${entry.name}',
      themeId: entry.id,
    );
  }

  Future<void> applyThemeFromFile(String filePath) async {
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
    throw _unsupportedWidgetThemeFlow(
      action:
          'Widget theme installation is not supported in the declarative manifest flow yet.',
    );
  }

  Future<void> applyWidgetThemeFromUrl(
    String componentId,
    String url, {
    bool refresh = false,
  }) async {
    throw _unsupportedWidgetThemeFlow(
      action:
          'Widget theme installation is not supported in the declarative manifest flow yet.',
    );
  }

  Future<void> resetWidgetTheme(
    String componentId, {
    bool refresh = false,
  }) async {
    throw _unsupportedWidgetThemeFlow(
      action:
          'Widget theme reset is not supported in the declarative manifest flow yet.',
    );
  }

  Future<void> applyThemeFromJson(
    Map<String, dynamic> data, {
    String? sourceLabel,
  }) async {
    final resolved = await _resolveThemeRegistry(refresh: false);
    final manifest = _parseThemeArtifactManifest(data);
    await _applyThemeArtifactManifest(
      manifest,
      registryId:
          resolved?.registryId ?? _themeRegistryId(registry.sourceRoot.root),
      registryBaseUrl: resolved?.registryBaseUrl ??
          registryBaseUrlOverride ??
          registry.sourceRoot.root,
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
    final entries = await _loadResolvedThemeEntries(refresh: refresh);
    if (entries.isEmpty) {
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
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final isCurrent = entry.id == config.themeId;
      final suffix = isCurrent ? ' (current)' : '';
      logger.info('  ${i + 1}) ${entry.name} (${entry.id})$suffix');
    }
    stdout.write('Theme number: ');
    final input = stdin.readLineSync();
    if (input == null || input.trim().isEmpty) {
      logger.info('Skipping theme selection.');
      return;
    }
    final trimmed = input.trim();
    ThemeIndexEntry? chosen;
    final index = int.tryParse(trimmed);
    if (index != null && index >= 1 && index <= entries.length) {
      chosen = entries[index - 1];
    } else {
      chosen = _findThemeIndexEntry(trimmed, entries);
    }
    if (chosen == null) {
      logger.warn('Invalid selection. Skipping theme selection.');
      return;
    }
    await applyThemeById(chosen.id, refresh: refresh);
  }

  Future<List<ThemeIndexEntry>> _loadResolvedThemeEntries({
    bool refresh = false,
  }) async {
    final resolved = await _resolveThemeRegistry(refresh: refresh);
    if (resolved == null) {
      return const <ThemeIndexEntry>[];
    }
    return resolved.indexEntries;
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
    final Map<String, dynamic> indexData;
    final List<ThemeIndexEntry> entries;
    try {
      indexData = await indexLoader.load();
      entries = indexLoader.entriesFrom(indexData);
    } finally {
      indexLoader.close();
    }
    return _ResolvedThemeRegistry(
      registryId: registryId,
      registryBaseUrl: registryBaseUrl,
      themesPath: themesPath,
      themesSchemaPath: themesSchemaPathOverride ?? entry?.themesSchemaPath,
      cacheRootPath: _themeCacheRootPath(registryId),
      indexEntries: entries,
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
      refresh: refresh,
      offline: registry.sourceRoot.offline,
      logger: logger,
      cacheRootPath: resolved.cacheRootPath,
    );
  }

  Future<_ThemeArtifactManifest> _loadThemeArtifactManifestById({
    required _ResolvedThemeRegistry resolved,
    required ThemeIndexEntry entry,
  }) async {
    if (entry.files.isNotEmpty) {
      return _parseThemeArtifactManifest(entry.toJson());
    }
    final presetLoader = _buildThemePresetLoader(resolved, refresh: false);
    final File manifestFile;
    try {
      manifestFile = await presetLoader.cachePresetJson(entry);
    } finally {
      presetLoader.close();
    }
    final content = await manifestFile.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Theme preset payload must be a JSON object.',
      );
    }
    return _parseThemeArtifactManifest(decoded);
  }

  _ThemeArtifactManifest _parseThemeArtifactManifest(
      Map<String, dynamic> data) {
    final rawFiles = data['files'];
    if (rawFiles is! List || rawFiles.isEmpty) {
      throw const FormatException(
        'Expected a declarative theme manifest with a non-empty "files" array.',
      );
    }
    final files = <_ThemeArtifactFile>[];
    for (final entry in rawFiles) {
      if (entry is! Map) {
        throw const FormatException(
          'Each theme manifest file entry must be an object.',
        );
      }
      final json = entry.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final source = json['source']?.toString().trim() ?? '';
      final target =
          (json['target'] ?? json['destination'])?.toString().trim() ?? '';
      final hash = json['sha256']?.toString().trim() ?? '';
      if (source.isEmpty || target.isEmpty || hash.isEmpty) {
        throw const FormatException(
          'Each theme manifest file entry must include source, target, and sha256.',
        );
      }
      files.add(
        _ThemeArtifactFile(
          source: source,
          target: target,
          sha256: hash,
        ),
      );
    }
    return _ThemeArtifactManifest(
      id: _themeIdFromPayload(data),
      name: _themeNameFromPayload(data),
      files: List.unmodifiable(files),
    );
  }

  Future<void> _applyThemeArtifactManifest(
    _ThemeArtifactManifest manifest, {
    required String registryId,
    required String registryBaseUrl,
    required String successMessage,
    String? themeId,
  }) async {
    await _ensureConfigLoaded();
    logger.progress(
      'Applying theme artifacts '
      '(${manifest.files.length} ${manifest.files.length == 1 ? 'file' : 'files'})',
    );
    final prepared = await _prepareThemeArtifacts(
      manifest: manifest,
      registryId: registryId,
      registryBaseUrl: registryBaseUrl,
    );
    for (final artifact in prepared) {
      await _atomicWriteBytes(artifact.targetFile, artifact.bytes);
    }
    if (themeId != null && themeId.isNotEmpty) {
      final config = await ShadcnConfig.load(targetDir);
      await ShadcnConfig.save(targetDir, config.copyWith(themeId: themeId));
    }
    logger.success(successMessage);
  }

  Future<List<_PreparedThemeArtifact>> _prepareThemeArtifacts({
    required _ThemeArtifactManifest manifest,
    required String registryId,
    required String registryBaseUrl,
  }) async {
    final prepared = <_PreparedThemeArtifact>[];
    final seenTargets = <String>{};
    for (final file in manifest.files) {
      final targetFile = File(_resolveDestinationPath(file.target));
      final normalizedTarget = p.normalize(targetFile.path);
      if (!seenTargets.add(normalizedTarget)) {
        throw ThemeInstallException(
          code: 'duplicate-target',
          message:
              'Theme manifest contains duplicate target path: ${file.target}',
        );
      }
      final bytes = await _readThemeArtifactBytes(
        registryBaseUrl: registryBaseUrl,
        source: file.source,
      );
      final actual = sha256.convert(bytes).toString().toLowerCase();
      final expected = file.sha256.toLowerCase();
      if (actual != expected) {
        throw ThemeInstallException(
          code: 'hash-mismatch',
          message:
              'SHA-256 mismatch for theme artifact ${file.source}: expected $expected but received $actual.',
        );
      }
      await _writeThemeArtifactCache(
        registryId: registryId,
        source: file.source,
        sha256Digest: expected,
        bytes: bytes,
      );
      prepared.add(
        _PreparedThemeArtifact(
          bytes: bytes,
          targetFile: targetFile,
        ),
      );
    }
    return prepared;
  }

  Future<List<int>> _readThemeArtifactBytes({
    required String registryBaseUrl,
    required String source,
  }) async {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Theme artifact source must not be empty.');
    }
    if (p.isAbsolute(trimmed)) {
      final file = File(trimmed);
      if (!file.existsSync()) {
        throw ThemeInstallException(
          code: 'source-not-found',
          message: 'Theme artifact source not found: $trimmed',
        );
      }
      return file.readAsBytes();
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) {
      if (uri.scheme == 'file') {
        final file = File(uri.toFilePath());
        if (!file.existsSync()) {
          throw ThemeInstallException(
            code: 'source-not-found',
            message: 'Theme artifact source not found: $trimmed',
          );
        }
        return file.readAsBytes();
      }
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        return _fetchThemeArtifactFromUri(uri);
      }
      throw ThemeInstallException(
        code: 'unsupported-source',
        message: 'Unsupported theme artifact source: $trimmed',
      );
    }

    final baseUri = Uri.tryParse(registryBaseUrl);
    final isRemoteBase =
        baseUri != null && baseUri.hasScheme && baseUri.scheme != 'file';
    final sourceRoot = isRemoteBase
        ? RegistryLocation.remote(
            registryBaseUrl,
            offline: registry.sourceRoot.offline,
          )
        : RegistryLocation.local(
            (baseUri != null && baseUri.scheme == 'file')
                ? baseUri.toFilePath()
                : registryBaseUrl,
            offline: registry.sourceRoot.offline,
          );
    return sourceRoot.readBytes(trimmed);
  }

  Future<List<int>> _fetchThemeArtifactFromUri(Uri uri) async {
    if (registry.sourceRoot.offline) {
      throw ThemeInstallException(
        code: 'offline-remote-source',
        message:
            'Offline mode: remote theme artifact not available for ${uri.toString()}.',
      );
    }
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ThemeInstallException(
          code: 'fetch-failed',
          message:
              'Failed to fetch theme artifact ${uri.toString()} (${response.statusCode}).',
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close();
    }
  }

  Future<File> _writeThemeArtifactCache({
    required String registryId,
    required String source,
    required String sha256Digest,
    required List<int> bytes,
  }) async {
    final basename = p.basename(source.trim().isEmpty ? 'artifact' : source);
    final extension = p.extension(basename);
    final stem = extension.isEmpty
        ? basename
        : basename.substring(0, basename.length - extension.length);
    final safeStem = stem.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final safeExtension = extension.replaceAll(RegExp(r'[^A-Za-z0-9.]'), '');
    final fileName =
        '${sha256Digest}_${safeStem.isEmpty ? 'artifact' : safeStem}$safeExtension';
    final cacheFile = File(
      _resolveProjectPath(
        p.join(
            '.shadcn', 'cache', 'registry', registryId, 'artifacts', fileName),
      ),
    );
    await _atomicWriteBytes(cacheFile, bytes);
    return cacheFile;
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

  String _themeRegistryId(String registryBaseUrl) {
    final safe = registryBaseUrl.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safe.length <= 80) {
      return safe;
    }
    return safe.substring(0, 80);
  }

  String _themeCacheRootPath(String registryId) {
    return _resolveProjectPath(
      p.join('.shadcn', 'cache', 'registry', registryId),
    );
  }

  Future<void> _atomicWriteBytes(File file, List<int> bytes) async {
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    final tempFile = File(_resolveProjectOrAbsolutePath('${file.path}.tmp'));
    await tempFile.writeAsBytes(bytes, flush: true);
    if (file.existsSync()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
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

  UnsupportedError _unsupportedWidgetThemeFlow({required String action}) {
    return UnsupportedError(
      '$action Widget theme commands remain experimental and are disabled for the non-executable manifest installer.',
    );
  }
}

class _ResolvedThemeRegistry {
  final String registryId;
  final String registryBaseUrl;
  final String themesPath;
  final String? themesSchemaPath;
  final String cacheRootPath;
  final List<ThemeIndexEntry> indexEntries;

  const _ResolvedThemeRegistry({
    required this.registryId,
    required this.registryBaseUrl,
    required this.themesPath,
    required this.themesSchemaPath,
    required this.cacheRootPath,
    required this.indexEntries,
  });
}

class ThemeInstallException implements Exception {
  final String code;
  final String message;

  const ThemeInstallException({
    required this.code,
    required this.message,
  });

  @override
  String toString() => 'ThemeInstallException($code): $message';
}

class _ThemeArtifactManifest {
  const _ThemeArtifactManifest({
    required this.id,
    required this.name,
    required this.files,
  });

  final String id;
  final String name;
  final List<_ThemeArtifactFile> files;
}

class _ThemeArtifactFile {
  const _ThemeArtifactFile({
    required this.source,
    required this.target,
    required this.sha256,
  });

  final String source;
  final String target;
  final String sha256;
}

class _PreparedThemeArtifact {
  const _PreparedThemeArtifact({
    required this.bytes,
    required this.targetFile,
  });

  final List<int> bytes;
  final File targetFile;
}
