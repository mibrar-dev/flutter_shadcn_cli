import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_shadcn_cli/registry/shared/theme/preset_theme_data.dart'
    show RegistryThemePresetData;
import 'package:flutter_shadcn_cli/src/infrastructure/io/process_runner.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry/theme_index_entry.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/validation/schema_validator.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/resolver_v1.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class ThemeManifestFileEntry {
  final String source;
  final String target;
  final String sha256;

  const ThemeManifestFileEntry({
    required this.source,
    required this.target,
    required this.sha256,
  });

  factory ThemeManifestFileEntry.fromJson(Map<String, dynamic> json) {
    return ThemeManifestFileEntry(
      source: json['source']?.toString().trim() ?? '',
      target: json['target']?.toString().trim() ?? '',
      sha256: json['sha256']?.toString().trim().toLowerCase() ?? '',
    );
  }
}

class ThemePresetManifest {
  final String id;
  final String name;
  final List<ThemeManifestFileEntry> files;

  const ThemePresetManifest({
    required this.id,
    required this.name,
    required this.files,
  });
}

class ThemePresetArtifact {
  final ThemeManifestFileEntry manifestFile;
  final List<int> bytes;
  final File cacheFile;

  const ThemePresetArtifact({
    required this.manifestFile,
    required this.bytes,
    required this.cacheFile,
  });
}

class ThemePresetLoader {
  static const _cacheDir = '~/.flutter_shadcn/cache';
  static const _stalenessDuration = Duration(hours: 24);
  static final _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

  final String registryId;
  final String registryBaseUrl;
  final String themesPath;
  final String? themesSchemaPath;
  final bool refresh;
  final bool offline;
  final CliLogger? logger;
  final SchemaValidator schemaValidator;
  final ProcessRunner processRunner;
  final String? cacheRootPath;

  ThemePresetLoader({
    required this.registryId,
    required this.registryBaseUrl,
    required this.themesPath,
    this.themesSchemaPath,
    this.refresh = false,
    this.offline = false,
    this.logger,
    this.cacheRootPath,
    SchemaValidator? schemaValidator,
    ProcessRunner? processRunner,
  })  : schemaValidator = schemaValidator ?? SchemaValidator(),
        processRunner = processRunner ?? const ProcessRunner();

  Future<RegistryThemePresetData> loadPreset(ThemeIndexEntry entry) async {
    final data = await _loadEntryJson(entry);
    await _validatePresetSchema(data);

    final parsed = _tryParsePresetJson(data);
    if (parsed != null) {
      return parsed;
    }

    if (_looksLikeManifest(data)) {
      throw Exception(
        'Theme "${entry.id}" is a declarative theme manifest and cannot be loaded as a color preset.',
      );
    }

    throw Exception(
      'Unsupported theme format for "${entry.id}". Expected light/dark colors or a declarative theme manifest.',
    );
  }

  Future<File> cachePresetJson(ThemeIndexEntry entry) async {
    final data = await _loadEntryJson(entry);
    final cacheFile = _manifestCacheFile(entry.id);
    _writeJsonCache(cacheFile, data);
    return cacheFile;
  }

  Future<ThemePresetManifest> loadManifest(ThemeIndexEntry entry) async {
    final data = await _loadEntryJson(entry);
    await _validatePresetSchema(data);
    return _parseManifest(data, entry);
  }

  Future<List<ThemePresetArtifact>> cacheArtifacts(
    ThemePresetManifest manifest,
  ) async {
    final artifacts = <ThemePresetArtifact>[];
    for (var i = 0; i < manifest.files.length; i++) {
      artifacts.add(await _cacheArtifact(manifest, manifest.files[i], i));
    }
    return artifacts;
  }

  bool verifySha256(List<int> bytes, String expectedDigest) {
    final normalized = expectedDigest.trim().toLowerCase();
    if (!_sha256Pattern.hasMatch(normalized)) {
      return false;
    }
    return sha256.convert(bytes).toString().toLowerCase() == normalized;
  }

  Future<Map<String, dynamic>> _loadEntryJson(ThemeIndexEntry entry) async {
    final cacheFile = _manifestCacheFile(entry.id);

    if (offline && cacheFile.existsSync()) {
      return _parseCache(cacheFile);
    }

    if (!refresh && !_isStale(cacheFile) && cacheFile.existsSync()) {
      try {
        return _parseCache(cacheFile);
      } catch (_) {}
    }

    if (offline) {
      throw Exception(
        'Offline mode: cached theme preset not found for ${entry.id}.',
      );
    }

    final content = await _readEntryContent(entry.file);
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw Exception('Theme entry "${entry.id}" must be a JSON object.');
    }
    final data = decoded.map((key, value) => MapEntry(key.toString(), value));
    _writeJsonCache(cacheFile, data);
    return data;
  }

  ThemePresetManifest _parseManifest(
    Map<String, dynamic> data,
    ThemeIndexEntry entry,
  ) {
    final filesRaw = data['files'];
    if (filesRaw is! List || filesRaw.isEmpty) {
      throw Exception(
        'Theme "${entry.id}" must be a declarative theme manifest with a non-empty "files" list.',
      );
    }

    final files = <ThemeManifestFileEntry>[];
    for (var i = 0; i < filesRaw.length; i++) {
      final rawFile = filesRaw[i];
      if (rawFile is! Map) {
        throw Exception(
          'Theme "${entry.id}" has an invalid file entry at index $i.',
        );
      }
      final fileEntry = ThemeManifestFileEntry.fromJson(
        rawFile.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (fileEntry.source.isEmpty || fileEntry.target.isEmpty) {
        throw Exception(
          'Theme "${entry.id}" file entry $i must include source and target.',
        );
      }
      if (!_sha256Pattern.hasMatch(fileEntry.sha256)) {
        throw Exception(
          'Theme "${entry.id}" file entry $i must include a valid SHA-256 digest.',
        );
      }
      files.add(fileEntry);
    }

    final rawId = data['id']?.toString().trim();
    final rawName = data['name']?.toString().trim();
    final id = (rawId == null || rawId.isEmpty) ? entry.id : rawId;
    final name = (rawName == null || rawName.isEmpty)
        ? (entry.name.trim().isEmpty ? id : entry.name.trim())
        : rawName;

    return ThemePresetManifest(id: id, name: name, files: files);
  }

  Future<ThemePresetArtifact> _cacheArtifact(
    ThemePresetManifest manifest,
    ThemeManifestFileEntry manifestFile,
    int index,
  ) async {
    final cacheFile = _artifactCacheFile(manifest.id, manifestFile, index);
    if (cacheFile.existsSync()) {
      final cachedBytes = cacheFile.readAsBytesSync();
      if (verifySha256(cachedBytes, manifestFile.sha256)) {
        return ThemePresetArtifact(
          manifestFile: manifestFile,
          bytes: cachedBytes,
          cacheFile: cacheFile,
        );
      }
      if (offline) {
        throw Exception(
          'Offline mode: cached theme artifact failed SHA-256 validation for ${manifestFile.source}.',
        );
      }
    } else if (offline) {
      throw Exception(
        'Offline mode: cached theme artifact not found for ${manifestFile.source}.',
      );
    }

    final bytes = await _readArtifactBytes(manifestFile.source);
    if (!verifySha256(bytes, manifestFile.sha256)) {
      throw Exception(
        'SHA-256 mismatch for theme artifact "${manifestFile.source}".',
      );
    }

    if (!cacheFile.parent.existsSync()) {
      cacheFile.parent.createSync(recursive: true);
    }
    cacheFile.writeAsBytesSync(bytes, flush: true);

    return ThemePresetArtifact(
      manifestFile: manifestFile,
      bytes: bytes,
      cacheFile: cacheFile,
    );
  }

  RegistryThemePresetData? _tryParsePresetJson(Map<String, dynamic> data) {
    final idRaw = data['id']?.toString().trim();
    final nameRaw = data['name']?.toString().trim();
    final light = _parseColorMap(data['light']);
    final dark = _parseColorMap(data['dark']);
    if (light == null || dark == null) {
      return null;
    }
    final id = (idRaw == null || idRaw.isEmpty) ? 'custom' : idRaw;
    final name = (nameRaw == null || nameRaw.isEmpty) ? id : nameRaw;
    return RegistryThemePresetData(
      id: id,
      name: name,
      light: light,
      dark: dark,
    );
  }

  Map<String, String>? _parseColorMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    final out = <String, String>{};
    value.forEach((key, val) {
      if (key == null || val == null) {
        return;
      }
      final k = key.toString().trim();
      final v = val.toString().trim();
      if (k.isNotEmpty && v.isNotEmpty) {
        out[k] = v;
      }
    });
    return out.isEmpty ? null : out;
  }

  bool _looksLikeManifest(Map<String, dynamic> data) {
    return data['files'] is List;
  }

  Future<String> _readEntryContent(String entryPath) async {
    return utf8.decode(
      await _readContentBytes(
        candidates: _themeEntryCandidates(entryPath),
        description: 'Theme entry',
        allowAbsoluteSource: true,
        originalPath: entryPath,
      ),
    );
  }

  Future<List<int>> _readArtifactBytes(String source) async {
    return _readContentBytes(
      candidates: _artifactSourceCandidates(source),
      description: 'Theme artifact',
      allowAbsoluteSource: true,
      originalPath: source,
    );
  }

  Future<List<int>> _readContentBytes({
    required List<String> candidates,
    required String description,
    required bool allowAbsoluteSource,
    required String originalPath,
  }) async {
    final explicitUri = Uri.tryParse(originalPath.trim());
    if (allowAbsoluteSource && explicitUri != null && explicitUri.hasScheme) {
      return _readAbsoluteUriBytes(explicitUri, description);
    }

    final localBase = _localBasePath();
    if (localBase != null) {
      for (final candidate in candidates) {
        final localFile = _resolveLocalFile(candidate);
        if (localFile != null && localFile.existsSync()) {
          return localFile.readAsBytesSync();
        }
      }
      throw Exception(
          '$description not found locally: ${candidates.join(', ')}');
    }

    Object lastError = Exception('$description not found.');
    for (final candidate in candidates) {
      try {
        final uri = ResolverV1.resolveUrl(registryBaseUrl, candidate);
        final response = await http.get(uri);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response.bodyBytes;
        }
        lastError =
            Exception('Failed ${uri.toString()} (${response.statusCode})');
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError;
  }

  Future<List<int>> _readAbsoluteUriBytes(Uri uri, String description) async {
    switch (uri.scheme) {
      case 'file':
        final file = File(uri.toFilePath());
        if (!file.existsSync()) {
          throw Exception('$description not found: ${uri.toFilePath()}');
        }
        return file.readAsBytesSync();
      case 'http':
      case 'https':
        final response = await http.get(uri);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(
            'Failed to fetch $description ${uri.toString()} (${response.statusCode})',
          );
        }
        return response.bodyBytes;
      default:
        throw Exception(
          'Unsupported $description URI scheme: ${uri.scheme}',
        );
    }
  }

  List<String> _themeEntryCandidates(String entryPath) {
    final normalized = ResolverV1.normalizeRelativePath(entryPath);
    final indexDir = p.posix.dirname(themesPath.replaceAll('\\', '/'));
    return _dedupeCandidates(<String>[
      if (indexDir != '.' && indexDir.isNotEmpty)
        p.posix.normalize(p.posix.join(indexDir, normalized)),
      ..._registryPathCandidates(normalized),
    ]);
  }

  List<String> _artifactSourceCandidates(String source) {
    final normalized = ResolverV1.normalizeRelativePath(source);
    return _registryPathCandidates(normalized);
  }

  List<String> _registryPathCandidates(String relativePath) {
    final normalized = ResolverV1.normalizeRelativePath(relativePath);
    final withoutRegistry = normalized.startsWith('registry/')
        ? normalized.substring('registry/'.length)
        : normalized;
    return _dedupeCandidates(<String>[
      normalized,
      withoutRegistry,
      if (!normalized.startsWith('registry/')) 'registry/$normalized',
    ]);
  }

  List<String> _dedupeCandidates(List<String> candidates) {
    final seen = <String>{};
    final deduped = <String>[];
    for (final candidate in candidates) {
      final normalized = candidate.trim();
      if (normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      deduped.add(normalized);
    }
    return deduped;
  }

  File _manifestCacheFile(String themeId) {
    final safeId =
        themeId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_').toLowerCase();
    final root = _cacheRootDir();
    return File(
      ProjectPathGuard.resolveSafeWritePath(
        projectRoot: root.path,
        destinationRelativePath: p.join('themes', safeId, 'manifest.json'),
      ),
    );
  }

  File _artifactCacheFile(
    String themeId,
    ThemeManifestFileEntry manifestFile,
    int index,
  ) {
    final safeId =
        themeId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_').toLowerCase();
    final cacheKey = sha256
        .convert(utf8.encode('${manifestFile.source}\n${manifestFile.target}'))
        .toString()
        .toLowerCase();
    final extension = p.extension(manifestFile.source);
    final baseName = p.basenameWithoutExtension(manifestFile.source);
    final safeBaseName =
        baseName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_').toLowerCase();
    final cacheName = '${index.toString().padLeft(2, '0')}_'
        '${cacheKey}_$safeBaseName${extension.isEmpty ? '.bin' : extension}';
    final root = _cacheRootDir();
    return File(
      ProjectPathGuard.resolveSafeWritePath(
        projectRoot: root.path,
        destinationRelativePath: p.join(
          'themes',
          safeId,
          'artifacts',
          cacheName,
        ),
      ),
    );
  }

  void _writeJsonCache(File cacheFile, Map<String, dynamic> data) {
    if (!cacheFile.parent.existsSync()) {
      cacheFile.parent.createSync(recursive: true);
    }
    cacheFile.writeAsStringSync(jsonEncode(data), flush: true);
  }

  Directory _cacheRootDir() {
    final rootPath = cacheRootPath?.trim().isNotEmpty == true
        ? cacheRootPath!.trim()
        : p.join(_cacheDir.replaceFirst('~', _homeDir()), registryId);
    final root = Directory(rootPath);
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }
    return root;
  }

  bool _isStale(File file) {
    if (!file.existsSync()) {
      return true;
    }
    final age = DateTime.now().difference(file.statSync().modified);
    return age > _stalenessDuration;
  }

  Map<String, dynamic> _parseCache(File file) {
    final content = file.readAsStringSync();
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw Exception('Cached theme manifest must be a JSON object.');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  String? _localBasePath() {
    final uri = Uri.tryParse(registryBaseUrl);
    if (uri != null && uri.hasScheme && uri.scheme != 'file') {
      return null;
    }
    if (uri != null && uri.scheme == 'file') {
      return uri.toFilePath();
    }
    return registryBaseUrl;
  }

  File? _resolveLocalFile(String relativePath) {
    final base = _localBasePath();
    if (base == null || base.isEmpty) {
      return null;
    }
    final normalizedBase = p.normalize(base);
    final normalizedRelative = relativePath.replaceAll('\\', '/');
    final direct = File(p.join(normalizedBase, normalizedRelative));
    if (direct.existsSync()) {
      return direct;
    }
    final nested = File(p.join(normalizedBase, 'registry', normalizedRelative));
    if (nested.existsSync()) {
      return nested;
    }
    return direct;
  }

  Future<void> _validatePresetSchema(Map<String, dynamic> data) async {
    final schemaPath = themesSchemaPath?.trim();
    if (schemaPath == null || schemaPath.isEmpty) {
      return;
    }
    final result = await schemaValidator.validate(
      data: data,
      baseUrl: registryBaseUrl,
      schemaPath: schemaPath,
      logger: logger,
    );
    if (!result.isValid) {
      logger?.warn(
        'theme preset schema validation failed (${result.errors.length} issues).',
      );
    }
  }

  static String _homeDir() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      return env['USERPROFILE'] ?? env['HOME'] ?? '.';
    }
    return env['HOME'] ?? '.';
  }
}
