import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/infrastructure/registry/theme_index_entry.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/validation/schema_validator.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/resolver_v1.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class ThemeIndexLoader {
  static const _cacheDir = '~/.flutter_shadcn/cache';
  static const _stalenessDuration = Duration(hours: 24);

  final String registryId;
  final String registryBaseUrl;
  final String themesPath;
  final String? themesSchemaPath;
  final bool refresh;
  final bool offline;
  final CliLogger? logger;
  final SchemaValidator schemaValidator;
  final String? cacheRootPath;

  ThemeIndexLoader({
    required this.registryId,
    required this.registryBaseUrl,
    required this.themesPath,
    this.themesSchemaPath,
    this.refresh = false,
    this.offline = false,
    this.logger,
    this.cacheRootPath,
    SchemaValidator? schemaValidator,
  }) : schemaValidator = schemaValidator ?? SchemaValidator();

  Future<Map<String, dynamic>> load() async {
    final cacheFile = _getCacheFile();
    final localPath = _resolveLocalPath();

    if (offline) {
      if (localPath != null) {
        final file = File(localPath);
        if (file.existsSync()) {
          final data = await _parse(file);
          await _validate(data);
          return data;
        }
      }
      if (cacheFile.existsSync()) {
        final data = await _parse(cacheFile);
        await _validate(data);
        return data;
      }
      throw Exception('Offline mode: cached theme.index.json not found.');
    }

    if (localPath != null) {
      final file = File(localPath);
      if (!file.existsSync()) {
        throw Exception('Theme index file not found: $localPath');
      }
      final data = await _parse(file);
      await _validate(data);
      await cacheFile.writeAsString(jsonEncode(data), flush: true);
      return data;
    }

    final shouldRefresh = refresh || _isStale(cacheFile);
    if (!shouldRefresh && cacheFile.existsSync()) {
      try {
        final data = await _parse(cacheFile);
        await _validate(data);
        return data;
      } catch (_) {}
    }

    try {
      final data = await _downloadAndCache();
      await _validate(data);
      return data;
    } catch (e) {
      if (cacheFile.existsSync()) {
        final data = await _parse(cacheFile);
        await _validate(data);
        return data;
      }
      rethrow;
    }
  }

  List<ThemeIndexEntry> entriesFrom(Map<String, dynamic> data) {
    final raw = data['themes'] ?? data['items'];
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map(
          (entry) => ThemeIndexEntry.fromJson(
            entry.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((entry) => entry.isValid)
        .toList();
  }

  String indexDirectory() {
    final normalized = themesPath.replaceAll('\\', '/');
    final dir = p.posix.dirname(normalized);
    return dir == '.' ? '' : dir;
  }

  File _getCacheFile() {
    final rootPath = cacheRootPath?.trim().isNotEmpty == true
        ? cacheRootPath!.trim()
        : p.join(_cacheDir.replaceFirst('~', _homeDir()), registryId);
    final cacheDir = Directory(rootPath);
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    return File(
      ProjectPathGuard.resolveSafeWritePath(
        projectRoot: cacheDir.path,
        destinationRelativePath: 'theme.index.json',
      ),
    );
  }

  bool _isStale(File file) {
    if (!file.existsSync()) {
      return true;
    }
    final age = DateTime.now().difference(file.statSync().modified);
    return age > _stalenessDuration;
  }

  Future<Map<String, dynamic>> _parse(File file) async {
    final content = await file.readAsString();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _downloadAndCache() async {
    final localPath = _resolveLocalPath();
    Map<String, dynamic> data;

    if (localPath != null) {
      final file = File(localPath);
      if (!file.existsSync()) {
        throw Exception('Theme index file not found: $localPath');
      }
      data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } else {
      final uri = ResolverV1.resolveUrl(
        registryBaseUrl,
        ResolverV1.normalizeRelativePath(themesPath),
      );
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Failed to fetch theme index ${uri.toString()} (${response.statusCode})',
        );
      }
      data = jsonDecode(response.body) as Map<String, dynamic>;
    }

    final cache = _getCacheFile();
    await cache.writeAsString(jsonEncode(data), flush: true);
    return data;
  }

  String? _resolveLocalPath() {
    final uri = Uri.tryParse(registryBaseUrl);
    String? basePath;
    if (uri != null && uri.hasScheme && uri.scheme != 'file') {
      return null;
    }
    if (uri != null && uri.scheme == 'file') {
      basePath = uri.toFilePath();
    } else {
      basePath = registryBaseUrl;
    }
    if (basePath.isEmpty) {
      return null;
    }

    final normalizedBase = p.normalize(basePath);
    final normalizedThemesPath =
        themesPath.trim().isEmpty ? 'theme.index.json' : themesPath.trim();
    final candidates = <String>[
      p.join(normalizedBase, normalizedThemesPath),
      p.join(normalizedBase, 'registry', normalizedThemesPath),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  Future<void> _validate(Map<String, dynamic> data) async {
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
        'theme.index.json schema validation failed (${result.errors.length} issues).',
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
