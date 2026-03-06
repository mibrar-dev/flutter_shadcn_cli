import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/registry/shared/theme/preset_theme_data.dart'
    show RegistryThemePresetData;
import 'package:flutter_shadcn_cli/src/infrastructure/io/process_runner.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry/theme_index_entry.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/validation/schema_validator.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/resolver_v1.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class ThemePresetLoader {
  static const _cacheDir = '~/.flutter_shadcn/cache';
  static const _stalenessDuration = Duration(hours: 24);

  final String registryId;
  final String registryBaseUrl;
  final String themesPath;
  final String? themesSchemaPath;
  final String? themeConverterDartPath;
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
    this.themeConverterDartPath,
    this.refresh = false,
    this.offline = false,
    this.logger,
    this.cacheRootPath,
    SchemaValidator? schemaValidator,
    ProcessRunner? processRunner,
  })  : schemaValidator = schemaValidator ?? SchemaValidator(),
        processRunner = processRunner ?? const ProcessRunner();

  Future<RegistryThemePresetData> loadPreset(ThemeIndexEntry entry) async {
    final data = await _loadPresetJson(entry);
    await _validatePresetSchema(data);

    final parsed = _tryParsePresetJson(data);
    if (parsed != null) {
      return parsed;
    }

    final converted = await _convertWithRegistryScript(data, entry.id);
    if (converted != null) {
      final parsedConverted = _tryParsePresetJson(converted);
      if (parsedConverted != null) {
        return parsedConverted;
      }
      throw Exception(
        'Theme converter output is invalid for "${entry.id}". Expected id/name/light/dark.',
      );
    }

    throw Exception(
      'Unsupported theme format for "${entry.id}". No compatible converter configured.',
    );
  }

  Future<File> cachePresetJson(ThemeIndexEntry entry) async {
    await _loadPresetJson(entry);
    return _cacheFile(entry.id);
  }

  Future<Map<String, dynamic>> _loadPresetJson(ThemeIndexEntry entry) async {
    final cacheFile = _cacheFile(entry.id);

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
          'Offline mode: cached theme preset not found for ${entry.id}.');
    }

    final content = await _readPresetContent(entry.file);
    final data = jsonDecode(content) as Map<String, dynamic>;

    if (!cacheFile.parent.existsSync()) {
      cacheFile.parent.createSync(recursive: true);
    }
    cacheFile.writeAsStringSync(jsonEncode(data), flush: true);
    return data;
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

  Future<Map<String, dynamic>?> _convertWithRegistryScript(
    Map<String, dynamic> raw,
    String themeId,
  ) async {
    final converterPath = themeConverterDartPath?.trim();
    if (converterPath == null || converterPath.isEmpty) {
      return null;
    }

    final scriptFile = await _resolveConverterScriptFile(converterPath);
    if (scriptFile == null || !scriptFile.existsSync()) {
      logger?.warn('Theme converter script not found: $converterPath');
      return null;
    }

    final tempDir = Directory.systemTemp.createTempSync('theme_converter_');
    try {
      final inputFile = File(p.join(tempDir.path, '$themeId.json'));
      inputFile.writeAsStringSync(jsonEncode(raw), flush: true);

      final result = await processRunner.run(
        'dart',
        [scriptFile.path, inputFile.path],
      );

      if (result.exitCode != 0) {
        final stderr = result.stderr.toString().trim();
        throw Exception(
          'Theme converter failed for "$themeId" (exit ${result.exitCode}): $stderr',
        );
      }

      final stdout = result.stdout.toString().trim();
      if (stdout.isEmpty) {
        throw Exception(
            'Theme converter returned empty output for "$themeId".');
      }
      final decoded = jsonDecode(stdout);
      if (decoded is! Map) {
        throw Exception('Theme converter output must be a JSON object.');
      }
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } finally {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  }

  Future<File?> _resolveConverterScriptFile(String converterPath) async {
    final cacheFile = _converterCacheFile();
    final converterUri = Uri.tryParse(converterPath);
    if (converterUri != null && converterUri.hasScheme) {
      if (converterUri.scheme == 'file') {
        final localFile = File(converterUri.toFilePath());
        if (!localFile.existsSync()) {
          logger?.warn('Theme converter script not found: $converterPath');
          return null;
        }
        if (!cacheFile.parent.existsSync()) {
          cacheFile.parent.createSync(recursive: true);
        }
        cacheFile.writeAsBytesSync(localFile.readAsBytesSync(), flush: true);
        return cacheFile;
      }
      if (converterUri.scheme == 'http' || converterUri.scheme == 'https') {
        if (offline && cacheFile.existsSync()) {
          return cacheFile;
        }
        if (offline) {
          return null;
        }
        final response = await http.get(converterUri);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          logger?.warn(
            'Failed to fetch converter script ${converterUri.toString()} (${response.statusCode}).',
          );
          return null;
        }
        if (!cacheFile.parent.existsSync()) {
          cacheFile.parent.createSync(recursive: true);
        }
        cacheFile.writeAsBytesSync(response.bodyBytes, flush: true);
        return cacheFile;
      }
      logger?.warn('Unsupported converter URI scheme: ${converterUri.scheme}');
      return null;
    }

    final local = _resolveLocalFile(converterPath);
    if (local != null && local.existsSync()) {
      if (!cacheFile.parent.existsSync()) {
        cacheFile.parent.createSync(recursive: true);
      }
      cacheFile.writeAsBytesSync(local.readAsBytesSync(), flush: true);
      return cacheFile;
    }

    if (offline && cacheFile.existsSync()) {
      return cacheFile;
    }

    if (offline) {
      return null;
    }

    final normalizedPath = ResolverV1.normalizeRelativePath(converterPath);
    final uri = ResolverV1.resolveUrl(registryBaseUrl, normalizedPath);
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      logger?.warn(
        'Failed to fetch converter script ${uri.toString()} (${response.statusCode}).',
      );
      return null;
    }

    if (!cacheFile.parent.existsSync()) {
      cacheFile.parent.createSync(recursive: true);
    }
    cacheFile.writeAsBytesSync(response.bodyBytes, flush: true);
    return cacheFile;
  }

  Future<String> _readPresetContent(String filePath) async {
    final normalized = ResolverV1.normalizeRelativePath(filePath);
    final indexDir = p.posix.dirname(themesPath.replaceAll('\\', '/'));
    final candidates = <String>{
      if (indexDir != '.' && indexDir.isNotEmpty)
        p.posix.normalize(p.posix.join(indexDir, normalized)),
      normalized,
    }.toList();

    final localBase = _localBasePath();
    if (localBase != null) {
      for (final candidate in candidates) {
        final localFile = _resolveLocalFile(candidate);
        if (localFile != null && localFile.existsSync()) {
          return localFile.readAsStringSync();
        }
      }
      throw Exception(
          'Theme preset file not found locally: ${candidates.join(', ')}');
    }

    Object lastError = Exception('Theme preset file not found.');
    for (final candidate in candidates) {
      try {
        final uri = ResolverV1.resolveUrl(registryBaseUrl, candidate);
        final response = await http.get(uri);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response.body;
        }
        lastError =
            Exception('Failed ${uri.toString()} (${response.statusCode})');
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError;
  }

  File _cacheFile(String themeId) {
    final safeId =
        themeId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_').toLowerCase();
    final root = _cacheRootDir();
    return File(p.join(root.path, 'themes', '$safeId.json'));
  }

  File _converterCacheFile() {
    final root = _cacheRootDir();
    return File(p.join(root.path, 'themes', 'theme_converter.dart'));
  }

  Directory _cacheRootDir() {
    final rootPath = cacheRootPath?.trim().isNotEmpty == true
        ? cacheRootPath!.trim()
        : p.join(_cacheDir.replaceFirst('~', _homeDir()), registryId);
    return Directory(rootPath);
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
    return jsonDecode(content) as Map<String, dynamic>;
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
