import 'dart:convert';
import 'dart:io';
import 'package:flutter_shadcn_cli/src/infrastructure/validation/schema_validator.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/resolver_v1.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Manages loading and caching of registry index.json with staleness checking.
class IndexLoader {
  static const _cacheDir = '~/.flutter_shadcn/cache';
  static const _stalenessDuration = Duration(hours: 24);

  final String registryId;
  final String registryBaseUrl;
  final String indexPath;
  final String? indexSchemaPath;
  final bool refresh;
  final bool offline;
  final CliLogger? logger;
  final SchemaValidator schemaValidator;

  IndexLoader({
    required this.registryId,
    required this.registryBaseUrl,
    this.indexPath = 'index.json',
    this.indexSchemaPath,
    this.refresh = false,
    this.offline = false,
    this.logger,
    SchemaValidator? schemaValidator,
  }) : schemaValidator = schemaValidator ?? SchemaValidator();

  /// Loads index.json from cache or remote, with staleness checking.
  ///
  /// Returns the parsed JSON if available, otherwise throws an exception.
  ///
  /// Strategy:
  /// 1. Check cache directory for existing index.json
  /// 2. If missing or stale (more than 24h old), download from {registryBaseUrl}/dist/index.json
  /// 3. Cache the downloaded file
  /// 4. Parse and return as Map
  Future<Map<String, dynamic>> load() async {
    final cacheFile = _getCacheFile();
    if (offline) {
      final localPath = _resolveLocalIndexPath();
      if (localPath != null) {
        final file = File(localPath);
        if (file.existsSync()) {
          final data = await _parseCache(file);
          await _validateIndexSchema(data);
          return data;
        }
      }
      if (cacheFile.existsSync()) {
        final data = await _parseCache(cacheFile);
        await _validateIndexSchema(data);
        return data;
      }
      throw Exception('Offline mode: cached index.json not found.');
    }

    final shouldRefresh = refresh || _isStale(cacheFile);

    if (!shouldRefresh && cacheFile.existsSync()) {
      try {
        final data = await _parseCache(cacheFile);
        await _validateIndexSchema(data);
        return data;
      } catch (e) {
        // Cache corrupted, fall through to download
      }
    }

    // Download from remote
    try {
      final data = await _downloadAndCache();
      await _validateIndexSchema(data);
      return data;
    } catch (e) {
      if (cacheFile.existsSync()) {
        try {
          final data = await _parseCache(cacheFile);
          await _validateIndexSchema(data);
          return data;
        } catch (_) {
          // ignore cache fallback
        }
      }
      rethrow;
    }
  }

  /// Gets or creates the cache file path.
  File _getCacheFile() {
    final expandedPath = _cacheDir.replaceFirst('~', _getHomeDir());
    final cacheDir = Directory(p.join(expandedPath, registryId));

    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    return File(p.join(cacheDir.path, 'index.json'));
  }

  /// Returns true if cache file exists and is older than 24 hours.
  bool _isStale(File cacheFile) {
    if (!cacheFile.existsSync()) return true;

    final stat = cacheFile.statSync();
    final age = DateTime.now().difference(stat.modified);
    return age > _stalenessDuration;
  }

  /// Parses cache file as JSON.
  Future<Map<String, dynamic>> _parseCache(File cacheFile) async {
    final content = await cacheFile.readAsString();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  /// Downloads index.json from remote registry and caches it.
  Future<Map<String, dynamic>> _downloadAndCache() async {
    final localPath = _resolveLocalIndexPath();
    Map<String, dynamic> data;

    if (localPath != null) {
      final file = File(localPath);
      if (!file.existsSync()) {
        throw Exception('Index file not found: $localPath');
      }
      final content = await file.readAsString();
      data = jsonDecode(content) as Map<String, dynamic>;
    } else {
      final url = _resolveIndexUrl();
      final response = await http.get(Uri.parse(url));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Failed to fetch index.json from $url (${response.statusCode})',
        );
      }

      data = jsonDecode(response.body) as Map<String, dynamic>;
    }

    // Cache the downloaded file
    final cacheFile = _getCacheFile();
    await cacheFile.writeAsString(
      jsonEncode(data),
      flush: true,
    );

    return data;
  }

  /// Resolves the full URL to the remote index.json.
  String _resolveIndexUrl() {
    final path = ResolverV1.normalizeRelativePath(indexPath);
    return ResolverV1.resolveUrl(registryBaseUrl, path).toString();
  }

  String? _resolveLocalIndexPath() {
    final base = registryBaseUrl;
    final uri = Uri.tryParse(base);
    String? basePath;

    if (uri != null && uri.hasScheme && uri.scheme != 'file') {
      return null;
    }

    if (uri != null && uri.scheme == 'file') {
      basePath = uri.toFilePath();
    } else {
      basePath = base;
    }

    if (basePath.isEmpty) {
      return null;
    }

    final normalized = p.normalize(basePath);
    final normalizedIndexPath =
        indexPath.trim().isEmpty ? 'index.json' : indexPath;
    final candidates = <String>[
      p.join(normalized, normalizedIndexPath),
      p.join(normalized, 'registry', normalizedIndexPath),
      p.join(normalized, 'index.json'),
      p.join(normalized, 'registry', 'index.json'),
    ];

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }

    return null;
  }

  /// Returns the user's home directory.
  static String _getHomeDir() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      return env['USERPROFILE'] ?? env['HOME'] ?? '.';
    }
    return env['HOME'] ?? '.';
  }

  Future<void> _validateIndexSchema(Map<String, dynamic> data) async {
    final schemaPath = indexSchemaPath?.trim();
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
        'index.json schema validation failed (${result.errors.length} issues).',
      );
    }
  }
}
