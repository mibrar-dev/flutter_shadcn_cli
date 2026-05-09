import 'dart:convert';
import 'dart:io';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_file_selection_policy.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';

Future<int> runAuditCommand({
  required Registry registry,
  required String targetDir,
  required ShadcnConfig config,
  required bool jsonOutput,
  required CliLogger logger,
}) async {
  final errors = <Map<String, dynamic>>[];
  final warnings = <Map<String, dynamic>>[];

  final defaults = (registry.data['defaults'] as Map?)
          ?.map((key, value) => MapEntry(key.toString(), value.toString())) ??
      const <String, String>{};
  final installPath =
      config.installPath ?? defaults['installPath'] ?? 'lib/ui/shadcn';
  final sharedPath =
      config.sharedPath ?? defaults['sharedPath'] ?? 'lib/ui/shadcn/shared';
  final aliases = config.pathAliases ?? const <String, String>{};
  final resolvedInstallPath = _expandAliasPath(installPath, aliases);
  final resolvedSharedPath = _expandAliasPath(sharedPath, aliases);
  final installPathOnDisk = _ensureLibPrefix(resolvedInstallPath);
  final sharedPathOnDisk = _ensureLibPrefix(resolvedSharedPath);
  const fileSelectionPolicy = InstallerFileSelectionPolicy();

  final manifests = await _loadComponentManifests(targetDir, installPathOnDisk);
  final installedIds = manifests.keys.toList()..sort();

  final missingRegistry = <String>[];
  final versionMismatches = <Map<String, String>>[];
  final tagMismatches = <Map<String, dynamic>>[];
  final missingFiles = <String>[];
  final missingManifests = <String>[];

  for (final id in installedIds) {
    final manifest = manifests[id];
    if (manifest == null) {
      missingManifests.add(id);
      continue;
    }
    final component = registry.getComponent(id);
    if (component == null) {
      missingRegistry.add(id);
      continue;
    }

    final manifestVersion = manifest['version']?.toString();
    final registryVersion = component.version;
    if (manifestVersion != null &&
        registryVersion != null &&
        manifestVersion != registryVersion) {
      versionMismatches.add({
        'id': id,
        'installed': manifestVersion,
        'registry': registryVersion,
      });
    }

    final manifestTags = (manifest['tags'] as List?)?.cast<String>() ?? [];
    final registryTags = component.tags;
    if (manifestTags.toSet().difference(registryTags.toSet()).isNotEmpty ||
        registryTags.toSet().difference(manifestTags.toSet()).isNotEmpty) {
      tagMismatches.add({
        'id': id,
        'installed': manifestTags,
        'registry': registryTags,
      });
    }

    for (final file in component.files) {
      final destination = _resolveComponentDestination(
        targetDir,
        installPathOnDisk,
        sharedPathOnDisk,
        file,
      );
      if (!fileSelectionPolicy.shouldInstallFile(destination, config)) {
        continue;
      }
      if (!File(destination).existsSync()) {
        missingFiles.add('$id -> $destination');
      }
    }
  }

  if (missingRegistry.isNotEmpty) {
    errors.add(jsonError(
      code: ExitCodeLabels.componentMissing,
      message: 'Installed components missing from registry.',
      details: {'missing': missingRegistry},
    ));
  }
  if (missingFiles.isNotEmpty) {
    errors.add(jsonError(
      code: ExitCodeLabels.fileMissing,
      message: 'Missing installed files.',
      details: {'missing': missingFiles},
    ));
  }
  if (versionMismatches.isNotEmpty) {
    warnings.add(jsonWarning(
      code: ExitCodeLabels.validationFailed,
      message: 'Version mismatches detected.',
      details: {'mismatches': versionMismatches},
    ));
  }
  if (tagMismatches.isNotEmpty) {
    warnings.add(jsonWarning(
      code: ExitCodeLabels.validationFailed,
      message: 'Tag mismatches detected.',
      details: {'mismatches': tagMismatches},
    ));
  }
  if (missingManifests.isNotEmpty) {
    warnings.add(jsonWarning(
      code: ExitCodeLabels.validationFailed,
      message: 'Missing per-component manifests.',
      details: {'missing': missingManifests},
    ));
  }

  final exitCode =
      errors.isEmpty ? ExitCodes.success : ExitCodes.validationFailed;

  if (jsonOutput) {
    final payload = jsonEnvelope(
      command: 'audit',
      data: {
        'installed': installedIds,
        'missingRegistry': missingRegistry,
        'versionMismatches': versionMismatches,
        'tagMismatches': tagMismatches,
        'missingFiles': missingFiles,
        'missingManifests': missingManifests,
      },
      errors: errors,
      warnings: warnings,
      meta: {
        'exitCode': exitCode,
      },
    );
    printJson(payload);
    return exitCode;
  }

  logger.header('Component audit');
  logger.info('Installed components: ${installedIds.length}');

  if (missingRegistry.isEmpty) {
    logger.success('Registry coverage: OK');
  } else {
    logger.error('Missing from registry: ${missingRegistry.join(', ')}');
  }

  if (missingFiles.isEmpty) {
    logger.success('Files: OK');
  } else {
    logger.error('Missing files:');
    for (final entry in missingFiles.take(12)) {
      logger.info('  - $entry');
    }
  }

  if (versionMismatches.isNotEmpty) {
    logger.warn('Version mismatches:');
    for (final entry in versionMismatches) {
      logger.info(
          '  - ${entry['id']}: ${entry['installed']} -> ${entry['registry']}');
    }
  }

  if (tagMismatches.isNotEmpty) {
    logger.warn('Tag mismatches:');
    for (final entry in tagMismatches) {
      logger.info('  - ${entry['id']}');
    }
  }

  if (missingManifests.isNotEmpty) {
    logger.warn('Missing manifests: ${missingManifests.join(', ')}');
  }

  return exitCode;
}

Future<Map<String, Map<String, dynamic>>> _loadComponentManifests(
  String targetDir,
  String installPath,
) async {
  final manifests = <String, Map<String, dynamic>>{};
  final manifestDir = Directory(p.join(targetDir, '.shadcn', 'components'));
  if (manifestDir.existsSync()) {
    for (final entity in manifestDir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }
      try {
        final data = jsonDecode(entity.readAsStringSync());
        if (data is Map<String, dynamic>) {
          final id = data['id']?.toString();
          if (id != null && id.isNotEmpty) {
            manifests[id] = data;
          }
        }
      } catch (_) {
        continue;
      }
    }
    return manifests;
  }

  final fallback = File(p.join(targetDir, installPath, 'components.json'));
  if (!fallback.existsSync()) {
    return manifests;
  }
  try {
    final data = jsonDecode(fallback.readAsStringSync());
    if (data is Map<String, dynamic>) {
      final installed = (data['installed'] as List?)?.cast<String>() ?? [];
      final meta =
          (data['componentMeta'] as Map?)?.cast<String, dynamic>() ?? {};
      for (final id in installed) {
        final entry = meta[id];
        if (entry is Map<String, dynamic>) {
          manifests[id] = {
            'id': id,
            ...entry,
          };
        } else {
          manifests[id] = {'id': id};
        }
      }
    }
  } catch (_) {
    return manifests;
  }
  return manifests;
}

String _resolveComponentDestination(
  String targetDir,
  String installPath,
  String sharedPath,
  RegistryFile file,
) {
  final source = file.source.replaceAll('\\', '/');
  const registryPrefix = 'registry/';
  if (source.startsWith(registryPrefix)) {
    final relative = source.substring(registryPrefix.length);
    return p.join(targetDir, installPath, relative);
  }
  var destination = file.destination;
  destination = destination.replaceAll('{installPath}', installPath);
  destination = destination.replaceAll('{sharedPath}', sharedPath);
  return p.join(targetDir, destination);
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
