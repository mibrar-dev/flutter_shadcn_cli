import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';

Future<int> runValidateCommand({
  required Registry registry,
  required RegistryLocation registryRoot,
  required RegistryLocation sourceRoot,
  required bool offline,
  required bool jsonOutput,
  required CliLogger logger,
}) async {
  final errors = <Map<String, dynamic>>[];
  final warnings = <Map<String, dynamic>>[];

  SchemaSource? schemaSource;
  bool? schemaValid;
  final schemaErrors = <String>[];

  try {
    schemaSource = ComponentsSchemaValidator.resolveSchemaSource(
      data: registry.data,
      registryRoot: registryRoot,
      schemaPathOverride: registry.schemaPath,
    );
    if (schemaSource != null) {
      final result = await ComponentsSchemaValidator.validateWithJsonSchema(
        registry.data,
        schemaSource,
      );
      schemaValid = result.isValid;
      schemaErrors.addAll(result.errors);
      if (!result.isValid) {
        errors.add(jsonError(
          code: ExitCodeLabels.schemaInvalid,
          message: 'Schema validation failed.',
          details: {
            'errorCount': result.errors.length,
            'errors': result.errors,
          },
        ));
      }
    } else {
      warnings.add(jsonWarning(
        code: ExitCodeLabels.schemaInvalid,
        message: 'Schema file not found.',
      ));
    }
  } catch (e) {
    schemaValid = false;
    schemaErrors.add('Failed to validate schema: $e');
    errors.add(jsonError(
      code: ExitCodeLabels.schemaInvalid,
      message: 'Schema validation failed.',
      details: {
        'errors': schemaErrors,
      },
    ));
  }

  final componentIds = registry.components.map((c) => c.id).toSet();
  final missingComponentDeps = <String>[];
  for (final component in registry.components) {
    for (final dep in component.dependsOn) {
      if (!componentIds.contains(dep)) {
        missingComponentDeps.add('${component.id} -> $dep');
      }
    }
  }
  if (missingComponentDeps.isNotEmpty) {
    errors.add(jsonError(
      code: ExitCodeLabels.componentMissing,
      message: 'Missing component dependencies.',
      details: {'missing': missingComponentDeps},
    ));
  }

  final fileSources = <String>{};
  for (final shared in registry.shared) {
    for (final file in shared.files) {
      fileSources.add(_normalizeRegistryPath(file.source));
    }
  }
  for (final component in registry.components) {
    for (final file in component.files) {
      fileSources.add(_normalizeRegistryPath(file.source));
    }
  }

  final missingFiles = <String>[];
  var checkedCount = 0;
  var skippedCount = 0;
  if (offline && sourceRoot.isRemote) {
    warnings.add(jsonWarning(
      code: ExitCodeLabels.offlineUnavailable,
      message: 'Offline mode: remote file existence checks skipped.',
    ));
    skippedCount = fileSources.length;
  } else {
    for (final source in fileSources) {
      checkedCount++;
      if (!await _sourceExists(sourceRoot, source)) {
        missingFiles.add(source);
      }
    }
  }

  if (missingFiles.isNotEmpty) {
    errors.add(jsonError(
      code: ExitCodeLabels.fileMissing,
      message: 'Missing registry source files.',
      details: {'missing': missingFiles},
    ));
  }

  final missingFileDeps = <String>[];
  final optionalMissingFileDeps = <String>[];
  for (final shared in registry.shared) {
    for (final file in shared.files) {
      _collectFileDepIssues(
        file,
        fileSources,
        missingFileDeps,
        optionalMissingFileDeps,
      );
    }
  }
  for (final component in registry.components) {
    for (final file in component.files) {
      _collectFileDepIssues(
        file,
        fileSources,
        missingFileDeps,
        optionalMissingFileDeps,
      );
    }
  }

  if (missingFileDeps.isNotEmpty) {
    errors.add(jsonError(
      code: ExitCodeLabels.fileMissing,
      message: 'Missing required file dependencies.',
      details: {'missing': missingFileDeps},
    ));
  }
  if (optionalMissingFileDeps.isNotEmpty) {
    warnings.add(jsonWarning(
      code: ExitCodeLabels.fileMissing,
      message: 'Missing optional file dependencies.',
      details: {'missing': optionalMissingFileDeps},
    ));
  }

  final hasErrors = errors.isNotEmpty;
  final exitCode = _resolveExitCode(
    hasErrors: hasErrors,
    schemaInvalid: schemaValid == false,
    missingComponents: missingComponentDeps.isNotEmpty,
    missingFiles: missingFiles.isNotEmpty || missingFileDeps.isNotEmpty,
  );

  if (jsonOutput) {
    final payload = jsonEnvelope(
      command: 'validate',
      data: {
        'schema': {
          'found': schemaSource != null,
          'valid': schemaValid,
          'errorCount': schemaErrors.length,
          'errors': schemaErrors,
        },
        'components': {
          'total': registry.components.length,
          'missingDependencies': missingComponentDeps,
        },
        'files': {
          'checked': checkedCount,
          'skipped': skippedCount,
          'missing': missingFiles,
        },
        'fileDependencies': {
          'missing': missingFileDeps,
          'missingOptional': optionalMissingFileDeps,
        },
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

  logger.header('Registry validation');
  logger.info('Schema: ${schemaSource?.label ?? '(not found)'}');
  if (schemaValid == true) {
    logger.success('Schema validation passed.');
  } else if (schemaValid == false) {
    logger.error('Schema validation failed (${schemaErrors.length} issues).');
  }

  if (missingComponentDeps.isEmpty) {
    logger.success('Component dependencies: OK');
  } else {
    logger.error('Missing component dependencies:');
    for (final dep in missingComponentDeps) {
      logger.info('  - $dep');
    }
  }

  if (missingFiles.isEmpty) {
    logger.success('Source files: OK');
  } else {
    logger.error('Missing source files:');
    for (final file in missingFiles.take(12)) {
      logger.info('  - $file');
    }
    if (missingFiles.length > 12) {
      logger.info('  ...and ${missingFiles.length - 12} more');
    }
  }

  if (missingFileDeps.isEmpty) {
    logger.success('File dependencies: OK');
  } else {
    logger.error('Missing file dependencies:');
    for (final dep in missingFileDeps) {
      logger.info('  - $dep');
    }
  }

  if (optionalMissingFileDeps.isNotEmpty) {
    logger.warn('Missing optional file dependencies:');
    for (final dep in optionalMissingFileDeps) {
      logger.info('  - $dep');
    }
  }

  return exitCode;
}

Future<bool> _sourceExists(RegistryLocation root, String source) async {
  if (!root.isRemote) {
    return File(p.join(root.root, source)).existsSync();
  }
  try {
    await root.readBytes(source);
    return true;
  } catch (_) {
    return false;
  }
}

void _collectFileDepIssues(
  RegistryFile file,
  Set<String> sources,
  List<String> missing,
  List<String> missingOptional,
) {
  if (file.dependsOn.isEmpty) {
    return;
  }
  for (final dep in file.dependsOn) {
    final normalized = _normalizeRegistryPath(dep.source);
    if (sources.contains(normalized)) {
      continue;
    }
    if (dep.optional) {
      missingOptional.add(dep.source);
    } else {
      missing.add(dep.source);
    }
  }
}

String _normalizeRegistryPath(String source) {
  final normalized = source.replaceAll('\\', '/');
  return p.posix.normalize(normalized);
}

int _resolveExitCode({
  required bool hasErrors,
  required bool schemaInvalid,
  required bool missingComponents,
  required bool missingFiles,
}) {
  if (!hasErrors) {
    return ExitCodes.success;
  }
  if (schemaInvalid && (missingComponents || missingFiles)) {
    return ExitCodes.validationFailed;
  }
  if (schemaInvalid) {
    return ExitCodes.schemaInvalid;
  }
  if (missingFiles) {
    return ExitCodes.fileMissing;
  }
  if (missingComponents) {
    return ExitCodes.componentMissing;
  }
  return ExitCodes.validationFailed;
}
