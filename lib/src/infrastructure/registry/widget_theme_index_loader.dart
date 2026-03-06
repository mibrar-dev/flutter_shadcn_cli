import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/infrastructure/registry/widget_theme_index_entry.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/resolver_v1.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class WidgetThemeIndexLoader {
  static const _cacheDir = '~/.flutter_shadcn/cache';
  static const _stalenessDuration = Duration(hours: 24);

  final String registryId;
  final String registryBaseUrl;
  final String widgetThemesPath;
  final bool refresh;
  final bool offline;
  final CliLogger? logger;
  final String? cacheRootPath;

  WidgetThemeIndexLoader({
    required this.registryId,
    required this.registryBaseUrl,
    required this.widgetThemesPath,
    this.refresh = false,
    this.offline = false,
    this.logger,
    this.cacheRootPath,
  });

  Future<Map<String, dynamic>> load() async {
    final cacheFile = _getCacheFile();

    if (offline) {
      final localPath = _resolveLocalPath();
      if (localPath != null) {
        final file = File(localPath);
        if (file.existsSync()) {
          return _parse(file);
        }
      }
      if (cacheFile.existsSync()) {
        return _parse(cacheFile);
      }
      throw Exception(
          'Offline mode: cached widget_theme.index.json not found.');
    }

    if (!refresh && !_isStale(cacheFile) && cacheFile.existsSync()) {
      try {
        return _parse(cacheFile);
      } catch (_) {}
    }

    try {
      return await _downloadAndCache();
    } catch (error) {
      if (cacheFile.existsSync()) {
        return _parse(cacheFile);
      }
      rethrow;
    }
  }

  List<WidgetThemeIndexEntry> entriesFrom(Map<String, dynamic> data) {
    final raw = data['components'] ?? data['widgets'] ?? data['items'];
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map(
          (entry) => WidgetThemeIndexEntry.fromJson(
            entry.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((entry) => entry.isValid)
        .toList();
  }

  File _getCacheFile() {
    final rootPath = cacheRootPath?.trim().isNotEmpty == true
        ? cacheRootPath!.trim()
        : p.join(_cacheDir.replaceFirst('~', _homeDir()), registryId);
    final cacheDir = Directory(rootPath);
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    return File(p.join(cacheDir.path, 'widget_theme.index.json'));
  }

  bool _isStale(File file) {
    if (!file.existsSync()) {
      return true;
    }
    final age = DateTime.now().difference(file.statSync().modified);
    return age > _stalenessDuration;
  }

  Future<Map<String, dynamic>> _downloadAndCache() async {
    final localPath = _resolveLocalPath();
    Map<String, dynamic> data;

    if (localPath != null) {
      final file = File(localPath);
      if (!file.existsSync()) {
        throw Exception('Widget theme index file not found: $localPath');
      }
      data = _parse(file);
    } else {
      final uri = ResolverV1.resolveUrl(
        registryBaseUrl,
        ResolverV1.normalizeRelativePath(widgetThemesPath),
      );
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Failed to fetch widget theme index ${uri.toString()} (${response.statusCode})',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Widget theme index must be a JSON object.');
      }
      data = decoded;
    }

    final cacheFile = _getCacheFile();
    await cacheFile.writeAsString(jsonEncode(data), flush: true);
    return data;
  }

  Map<String, dynamic> _parse(File file) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Widget theme index must be a JSON object.');
    }
    return decoded;
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
    final normalizedIndexPath = widgetThemesPath.trim().isEmpty
        ? 'widget_theme.index.json'
        : widgetThemesPath.trim();
    final candidates = <String>[
      p.join(normalizedBase, normalizedIndexPath),
      p.join(normalizedBase, 'registry', normalizedIndexPath),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  static String _homeDir() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      return env['USERPROFILE'] ?? env['HOME'] ?? '.';
    }
    return env['HOME'] ?? '.';
  }
}
