import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/infrastructure/io/process_runner.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/resolver_v1.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class RegistryThemeInstallOperation {
  final String type;
  final String path;
  final String? content;
  final String? find;
  final String? replace;
  final String? importStatement;
  final bool replaceAll;

  const RegistryThemeInstallOperation({
    required this.type,
    required this.path,
    this.content,
    this.find,
    this.replace,
    this.importStatement,
    this.replaceAll = false,
  });

  factory RegistryThemeInstallOperation.fromJson(Map<String, dynamic> json) {
    return RegistryThemeInstallOperation(
      type: json['type']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      content: json['content']?.toString(),
      find: json['find']?.toString(),
      replace: json['replace']?.toString(),
      importStatement: json['import']?.toString(),
      replaceAll: json['replaceAll'] == true,
    );
  }

  bool get isValid => type.trim().isNotEmpty && path.trim().isNotEmpty;
}

class RegistryThemeConverterResponse {
  final String scope;
  final String? resolvedNamespace;
  final String? resolvedComponent;
  final String? resolvedTargetThemeType;
  final List<RegistryThemeInstallOperation> operations;
  final Map<String, dynamic>? preview;
  final List<RegistryThemeConverterMessage> messages;

  const RegistryThemeConverterResponse({
    required this.scope,
    required this.operations,
    this.resolvedNamespace,
    this.resolvedComponent,
    this.resolvedTargetThemeType,
    this.preview,
    this.messages = const <RegistryThemeConverterMessage>[],
  });

  factory RegistryThemeConverterResponse.fromJson(Map<String, dynamic> json) {
    final installPlan = json['installPlan'];
    final rawOperations = installPlan is Map ? installPlan['operations'] : null;
    final operations = rawOperations is List
        ? rawOperations
            .whereType<Map>()
            .map(
              (entry) => RegistryThemeInstallOperation.fromJson(
                entry.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .where((entry) => entry.isValid)
            .toList()
        : const <RegistryThemeInstallOperation>[];
    final rawMessages = json['messages'];
    final messages = rawMessages is List
        ? rawMessages
            .whereType<Map>()
            .map(
              (entry) => RegistryThemeConverterMessage.fromJson(
                entry.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .where((entry) => entry.isValid)
            .toList()
        : const <RegistryThemeConverterMessage>[];
    return RegistryThemeConverterResponse(
      scope: json['scope']?.toString() ?? '',
      resolvedNamespace: json['resolvedNamespace']?.toString(),
      resolvedComponent: json['resolvedComponent']?.toString(),
      resolvedTargetThemeType: json['resolvedTargetThemeType']?.toString(),
      operations: operations,
      preview: (json['preview'] as Map?)?.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      messages: messages,
    );
  }
}

class RegistryThemeConverterMessage {
  final String level;
  final String text;

  const RegistryThemeConverterMessage({
    required this.level,
    required this.text,
  });

  factory RegistryThemeConverterMessage.fromJson(Map<String, dynamic> json) {
    return RegistryThemeConverterMessage(
      level: json['level']?.toString() ?? 'info',
      text: json['text']?.toString() ?? '',
    );
  }

  bool get isValid => text.trim().isNotEmpty;
}

class RegistryThemeConverterClient {
  final String registryId;
  final String registryBaseUrl;
  final String converterPath;
  final bool offline;
  final CliLogger? logger;
  final String? cacheRootPath;
  final ProcessRunner processRunner;

  RegistryThemeConverterClient({
    required this.registryId,
    required this.registryBaseUrl,
    required this.converterPath,
    this.offline = false,
    this.logger,
    this.cacheRootPath,
    ProcessRunner? processRunner,
  }) : processRunner = processRunner ?? const ProcessRunner();

  Future<RegistryThemeConverterResponse> execute(
    Map<String, dynamic> request,
  ) async {
    final scriptFile = await _resolveConverterScriptFile(converterPath);
    if (scriptFile == null || !scriptFile.existsSync()) {
      throw Exception('Theme converter script not found: $converterPath');
    }

    final tempDir = Directory.systemTemp.createTempSync('registry_theme_');
    try {
      final inputFile = File(p.join(tempDir.path, 'request.json'));
      inputFile.writeAsStringSync(jsonEncode(request), flush: true);

      final result = await processRunner.run(
        'dart',
        [scriptFile.path, inputFile.path],
      );
      if (result.exitCode != 0) {
        final stderr = result.stderr.toString().trim();
        throw Exception(
          'Theme converter failed (exit ${result.exitCode}): $stderr',
        );
      }
      final stdout = result.stdout.toString().trim();
      if (stdout.isEmpty) {
        throw Exception('Theme converter returned empty output.');
      }
      final decoded = jsonDecode(stdout);
      if (decoded is! Map) {
        throw Exception('Theme converter output must be a JSON object.');
      }
      return RegistryThemeConverterResponse.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } finally {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  }

  Future<File?> _resolveConverterScriptFile(String rawConverterPath) async {
    final cacheFile = _converterCacheFile();
    final converterUri = Uri.tryParse(rawConverterPath);
    if (converterUri != null && converterUri.hasScheme) {
      if (converterUri.scheme == 'file') {
        final localFile = File(converterUri.toFilePath());
        if (!localFile.existsSync()) {
          logger?.warn('Theme converter script not found: $rawConverterPath');
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

    final local = _resolveLocalFile(rawConverterPath);
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

    final normalizedPath = ResolverV1.normalizeRelativePath(rawConverterPath);
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

  File? _resolveLocalFile(String rawConverterPath) {
    final normalized = rawConverterPath.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final direct = File(normalized);
    if (direct.existsSync()) {
      return direct;
    }
    final normalizedBase = p.normalize(registryBaseUrl);
    final candidates = <String>[
      p.join(normalizedBase, normalized),
      p.join(normalizedBase, 'registry', normalized),
    ];
    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync()) {
        return file;
      }
    }
    return null;
  }

  File _converterCacheFile() {
    final rootPath = cacheRootPath?.trim().isNotEmpty == true
        ? cacheRootPath!.trim()
        : p.join(_cacheDir.replaceFirst('~', _homeDir()), registryId);
    final cacheDir = Directory(rootPath);
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    return File(p.join(cacheDir.path, 'theme_converter.dart'));
  }

  static const _cacheDir = '~/.flutter_shadcn/cache';

  static String _homeDir() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      return env['USERPROFILE'] ?? env['HOME'] ?? '.';
    }
    return env['HOME'] ?? '.';
  }
}
