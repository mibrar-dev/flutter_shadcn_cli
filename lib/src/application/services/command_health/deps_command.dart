import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';

Future<int> runDepsCommand({
  required Registry registry,
  required String targetDir,
  required ShadcnConfig config,
  required bool includeAll,
  required bool jsonOutput,
  required CliLogger logger,
}) async {
  final installedIds = await _loadInstalledComponents(targetDir, config);
  final componentIds = includeAll || installedIds.isEmpty
      ? registry.components.map((c) => c.id).toList()
      : installedIds;

  final requiredDeps = <String, Map<String, String>>{};
  for (final id in componentIds) {
    final component = registry.getComponent(id);
    if (component == null) {
      continue;
    }
    final deps = component.pubspec['dependencies'] as Map<String, dynamic>?;
    deps?.forEach((key, value) {
      if (value == null) {
        return;
      }
      requiredDeps.putIfAbsent(
              key, () => <String, String>{})[_normalizeDependencyValue(value)] =
          _formatDependencyValue(value);
    });
  }

  final pubspecDeps = _loadPubspecDependencies(targetDir);
  final results = <Map<String, dynamic>>[];
  for (final entry in requiredDeps.entries) {
    final installed = pubspecDeps[entry.key];
    final installedCanonical = installed == null
        ? null
        : _normalizeDependencyValue(installed.originalValue);
    final status = installed == null
        ? 'missing'
        : entry.value.containsKey(installedCanonical)
            ? 'ok'
            : 'mismatch';
    results.add({
      'package': entry.key,
      'required': entry.value.values.toList()..sort(),
      'installed': installed?.displayValue,
      'status': status,
    });
  }

  final missing = results.where((r) => r['status'] == 'missing').toList();
  final mismatched = results.where((r) => r['status'] == 'mismatch').toList();
  final exitCode = (missing.isEmpty && mismatched.isEmpty)
      ? ExitCodes.success
      : ExitCodes.validationFailed;

  if (jsonOutput) {
    final payload = jsonEnvelope(
      command: 'deps',
      data: {
        'components': componentIds,
        'dependencies': results,
      },
      warnings: [
        if (missing.isNotEmpty)
          jsonWarning(
            code: ExitCodeLabels.validationFailed,
            message: 'Missing dependencies in pubspec.yaml.',
            details: {'missing': missing},
          ),
        if (mismatched.isNotEmpty)
          jsonWarning(
            code: ExitCodeLabels.validationFailed,
            message: 'Dependency version mismatches.',
            details: {'mismatched': mismatched},
          ),
      ],
      meta: {
        'exitCode': exitCode,
      },
    );
    printJson(payload);
    return exitCode;
  }

  logger.header('Dependency audit');
  if (results.isEmpty) {
    logger.info('No registry dependencies found.');
    return ExitCodes.success;
  }
  for (final entry in results) {
    final pkg = entry['package'] as String;
    final required = (entry['required'] as List).join(', ');
    final installed = entry['installed']?.toString() ?? '(missing)';
    final status = entry['status'] as String;
    if (status == 'ok') {
      logger.success('✓ $pkg  $installed');
    } else if (status == 'missing') {
      logger.error('✗ $pkg  missing (required: $required)');
    } else {
      logger.warn('! $pkg  $installed (required: $required)');
    }
  }

  return exitCode;
}

Future<List<String>> _loadInstalledComponents(
  String targetDir,
  ShadcnConfig config,
) async {
  final installPath = config.installPath ?? 'lib/ui/shadcn';
  final resolvedInstallPath =
      _expandAliasPath(installPath, config.pathAliases ?? const {});
  final installPathOnDisk = _ensureLibPrefix(resolvedInstallPath);
  final manifest =
      File(p.join(targetDir, installPathOnDisk, 'components.json'));
  if (!manifest.existsSync()) {
    return [];
  }
  try {
    final data = jsonDecode(manifest.readAsStringSync());
    if (data is Map<String, dynamic>) {
      final installed = (data['installed'] as List?)?.cast<String>() ?? [];
      return installed;
    }
  } catch (_) {
    return [];
  }
  return [];
}

String _expandAliasPath(String path, Map<String, String> aliases) {
  if (aliases.isEmpty) {
    return path;
  }
  if (path.startsWith('@')) {
    final index = path.indexOf('/');
    final name = index == -1 ? path.substring(1) : path.substring(1, index);
    final aliasPath = aliases[name];
    if (aliasPath != null) {
      final suffix = index == -1 ? '' : path.substring(index + 1);
      return suffix.isEmpty ? aliasPath : p.join(aliasPath, suffix);
    }
  }
  return path;
}

String _ensureLibPrefix(String path) {
  if (path.startsWith('lib/')) {
    return path;
  }
  if (p.isAbsolute(path)) {
    return path;
  }
  return p.join('lib', path);
}

Map<String, _PubspecDependencyValue> _loadPubspecDependencies(
    String targetDir) {
  final pubspecFile = File(p.join(targetDir, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    return {};
  }
  final content = pubspecFile.readAsStringSync();
  final doc = loadYaml(content);
  final deps = <String, _PubspecDependencyValue>{};
  if (doc is YamlMap && doc['dependencies'] is YamlMap) {
    final yamlDeps = doc['dependencies'] as YamlMap;
    yamlDeps.forEach((key, value) {
      if (key is String) {
        deps[key] = _PubspecDependencyValue(
          originalValue: value,
          displayValue: _formatDependencyValue(value),
        );
      }
    });
  }
  return deps;
}

String _normalizeDependencyValue(dynamic value) {
  return jsonEncode(_canonicalDependencyValue(value));
}

String _formatDependencyValue(dynamic value) {
  final canonical = _canonicalDependencyValue(value);
  if (canonical is Map && canonical.length == 1 && canonical['sdk'] != null) {
    return 'sdk: ${canonical['sdk']}';
  }
  if (canonical is Map || canonical is List) {
    return canonical.toString();
  }
  return canonical?.toString() ?? '';
}

dynamic _canonicalDependencyValue(dynamic value) {
  if (value is YamlMap) {
    return Map.fromEntries(
      value.nodes.entries
          .map(
            (entry) => MapEntry(
              entry.key.value.toString(),
              _canonicalDependencyValue(entry.value.value),
            ),
          )
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key)),
    );
  }
  if (value is YamlList) {
    return value.nodes
        .map((node) => _canonicalDependencyValue(node.value))
        .toList();
  }
  if (value is Map) {
    return Map.fromEntries(
      value.entries
          .map(
            (entry) => MapEntry(
              entry.key.toString(),
              _canonicalDependencyValue(entry.value),
            ),
          )
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key)),
    );
  }
  if (value is List) {
    return value.map(_canonicalDependencyValue).toList();
  }
  final text = value?.toString().trim();
  if (text == null) {
    return '';
  }
  final sdkMatch = RegExp(r'^sdk:\s*(.+)$').firstMatch(text);
  if (sdkMatch != null) {
    return {'sdk': sdkMatch.group(1)!.trim()};
  }
  return text;
}

class _PubspecDependencyValue {
  final dynamic originalValue;
  final String displayValue;

  const _PubspecDependencyValue({
    required this.originalValue,
    required this.displayValue,
  });
}
