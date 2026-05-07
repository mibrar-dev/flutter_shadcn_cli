import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/arg_helpers.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/platform_targets.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/registry_selection.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/runtime_roots.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;

Future<int> runDoctorCommand(
  ResolvedRoots roots,
  ArgResults args,
  ShadcnConfig config,
) async {
  final offline = args['offline'] == true;
  final jsonOutput = args.command?['json'] == true;
  final logger = CliLogger(verbose: args['verbose'] == true);
  final selection = resolveRegistrySelection(args, roots, config, offline);
  final envRoot = Platform.environment['SHADCN_REGISTRY_ROOT'];
  final envUrl = Platform.environment['SHADCN_REGISTRY_URL'];
  final pubCache = Platform.environment['PUB_CACHE'] ??
      p.join(Platform.environment['HOME'] ?? '', '.pub-cache');
  final cachePath = componentsJsonCachePath(selection.registryRoot);
  final componentsSource = selection.registryRoot.describe(
    selection.componentsPath,
  );
  Map<String, dynamic>? registryData;
  SchemaSource? schemaSource;
  bool? schemaValid;
  final schemaErrors = <String>[];
  try {
    final content = await readComponentsJson(selection, offline: offline);
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) {
      registryData = decoded;
      schemaSource = ComponentsSchemaValidator.resolveSchemaSource(
        data: decoded,
        registryRoot: selection.registryRoot,
      );
    }
  } catch (e) {
    final message = e.toString();
    final exitCode = message.contains('Offline mode')
        ? ExitCodes.offlineUnavailable
        : ExitCodes.networkError;
    if (jsonOutput) {
      final payload = jsonEnvelope(
        command: 'doctor',
        data: {
          'registry': {
            'mode': selection.mode,
            'root': selection.registryRoot.root,
            'componentsJson': componentsSource,
            'cache': cachePath ?? '(local registry, no cache)',
          },
        },
        errors: [
          jsonError(
            code: message.contains('Offline mode')
                ? ExitCodeLabels.offlineUnavailable
                : ExitCodeLabels.networkError,
            message: message,
          ),
        ],
        meta: {
          'exitCode': exitCode,
        },
      );
      printJson(payload);
      return exitCode;
    }
    logger.error('Failed to load components.json: $message');
    return exitCode;
  }

  if (schemaSource != null && registryData != null) {
    try {
      final result = await ComponentsSchemaValidator.validateWithJsonSchema(
        registryData,
        schemaSource,
      );
      schemaValid = result.isValid;
      schemaErrors.addAll(result.errors);
    } catch (e) {
      schemaValid = false;
      schemaErrors.add('Failed to validate schema: $e');
    }
  }

  final defaults = (registryData?['defaults'] as Map?)
          ?.map((key, value) => MapEntry(key.toString(), value.toString())) ??
      const <String, String>{};
  final installPath =
      config.installPath ?? defaults['installPath'] ?? 'lib/ui/shadcn';
  final sharedPath =
      config.sharedPath ?? defaults['sharedPath'] ?? 'lib/ui/shadcn/shared';
  final aliases = config.pathAliases ?? const <String, String>{};
  final resolvedInstallPath = expandAliasPath(installPath, aliases);
  final resolvedSharedPath = expandAliasPath(sharedPath, aliases);
  final installPathOnDisk = ensureLibPrefix(resolvedInstallPath);
  final sharedPathOnDisk = ensureLibPrefix(resolvedSharedPath);
  final installPathValid = isLibPath(resolvedInstallPath);
  final sharedPathValid = isLibPath(resolvedSharedPath);
  final installPathExists =
      Directory(p.join(Directory.current.path, installPathOnDisk)).existsSync();
  final sharedPathExists =
      Directory(p.join(Directory.current.path, sharedPathOnDisk)).existsSync();
  final colorSchemePath = p.join(
    Directory.current.path,
    sharedPathOnDisk,
    'theme',
    'color_scheme.dart',
  );
  final colorSchemeExists = File(colorSchemePath).existsSync();
  final invalidAliases = <String>[];
  aliases.forEach((name, value) {
    final aliasPath = p.join(Directory.current.path, ensureLibPrefix(value));
    if (!Directory(aliasPath).existsSync()) {
      invalidAliases.add(name);
    }
  });

  final platformTargets = mergePlatformTargets(config.platformTargets);
  final lockRepository = ShadcnLockRepository(Directory.current.path);
  ShadcnLock lock = const ShadcnLock();
  final lockfileExists = lockRepository.file.existsSync();
  String? lockfileError;
  try {
    lock = await lockRepository.loadOrSynthesize();
  } catch (e) {
    lockfileError = e.toString();
  }
  final missingLockedFiles = <String>[];
  if (lockfileError == null) {
    for (final component in lock.components) {
      for (final relativePath in component.installedFiles) {
        if (!File(p.join(Directory.current.path, relativePath)).existsSync()) {
          missingLockedFiles.add('${component.qualifiedId}: $relativePath');
        }
      }
    }
  }

  final hasSchemaIssues = schemaValid == false;
  final hasConfigIssues = !installPathValid ||
      !sharedPathValid ||
      !colorSchemeExists ||
      invalidAliases.isNotEmpty;
  final warnings = <Map<String, dynamic>>[];
  final errors = <Map<String, dynamic>>[];

  if (!installPathExists) {
    warnings.add(jsonWarning(
      code: ExitCodeLabels.configInvalid,
      message: 'Install path does not exist.',
      details: {'path': resolvedInstallPath},
    ));
  }
  if (!sharedPathExists) {
    warnings.add(jsonWarning(
      code: ExitCodeLabels.configInvalid,
      message: 'Shared path does not exist.',
      details: {'path': resolvedSharedPath},
    ));
  }

  if (hasSchemaIssues) {
    errors.add(jsonError(
      code: ExitCodeLabels.schemaInvalid,
      message: 'Schema validation failed.',
      details: {
        'errorCount': schemaErrors.length,
        'errors': schemaErrors,
      },
    ));
  }
  if (!installPathValid) {
    errors.add(jsonError(
      code: ExitCodeLabels.configInvalid,
      message: 'Install path is not under lib/.',
      details: {'path': resolvedInstallPath},
    ));
  }
  if (!sharedPathValid) {
    errors.add(jsonError(
      code: ExitCodeLabels.configInvalid,
      message: 'Shared path is not under lib/.',
      details: {'path': resolvedSharedPath},
    ));
  }
  if (!colorSchemeExists) {
    errors.add(jsonError(
      code: ExitCodeLabels.configInvalid,
      message: 'color_scheme.dart is missing.',
      details: {'path': colorSchemePath},
    ));
  }
  if (invalidAliases.isNotEmpty) {
    errors.add(jsonError(
      code: ExitCodeLabels.configInvalid,
      message: 'One or more path aliases are invalid.',
      details: {'aliases': invalidAliases},
    ));
  }
  if (missingLockedFiles.isNotEmpty) {
    errors.add(jsonError(
      code: ExitCodeLabels.validationFailed,
      message: 'One or more locked component files are missing.',
      details: {'files': missingLockedFiles},
    ));
  }
  if (lockfileError != null) {
    errors.add(jsonError(
      code: ExitCodeLabels.validationFailed,
      message: 'Failed to parse shadcn.lock.',
      details: {'error': lockfileError},
    ));
  }

  var doctorExitCode = ExitCodes.success;
  final hasLockIssues = missingLockedFiles.isNotEmpty || lockfileError != null;
  if (hasSchemaIssues && (hasConfigIssues || hasLockIssues)) {
    doctorExitCode = ExitCodes.validationFailed;
  } else if (hasSchemaIssues) {
    doctorExitCode = ExitCodes.schemaInvalid;
  } else if (hasConfigIssues) {
    doctorExitCode = ExitCodes.configInvalid;
  } else if (hasLockIssues) {
    doctorExitCode = ExitCodes.validationFailed;
  }

  if (jsonOutput) {
    final payload = jsonEnvelope(
      command: 'doctor',
      data: {
        'environment': {
          'script': Platform.script.toFilePath(),
          'cwd': Directory.current.path,
          'pubCache': pubCache,
        },
        'registry': {
          'mode': selection.mode,
          'root': selection.registryRoot.root,
          'componentsJson': componentsSource,
          'cache': cachePath ?? '(local registry, no cache)',
          'schema': schemaSource?.label,
        },
        'configuration': {
          'SHADCN_REGISTRY_ROOT': envRoot,
          'SHADCN_REGISTRY_URL': envUrl,
          'cliRoot': roots.cliRoot,
          'localRegistryRoot': roots.localRegistryRoot,
          'config.registryMode': config.registryMode,
          'config.registryPath': config.registryPath,
          'config.registryUrl': config.registryUrl,
        },
        'paths': {
          'installPath': installPath,
          'sharedPath': sharedPath,
          'resolvedInstallPath': resolvedInstallPath,
          'resolvedSharedPath': resolvedSharedPath,
          'installPathValid': installPathValid,
          'sharedPathValid': sharedPathValid,
          'installPathExists': installPathExists,
          'sharedPathExists': sharedPathExists,
          'colorSchemePath': colorSchemePath,
          'colorSchemeExists': colorSchemeExists,
        },
        'aliases': {
          'configured': aliases,
          'invalid': invalidAliases,
        },
        'schema': {
          'found': schemaSource != null,
          'valid': schemaValid,
          'errorCount': schemaErrors.length,
          'errors': schemaErrors,
        },
        'platformTargets': platformTargets,
        'lockfile': {
          'exists': lockfileExists,
          'lockfileVersion': lock.lockfileVersion,
          'registryCount': lock.registries.length,
          'componentCount': lock.components.length,
          'missingFiles': missingLockedFiles,
          'error': lockfileError,
        },
      },
      errors: errors,
      warnings: warnings,
      meta: {
        'exitCode': doctorExitCode,
      },
    );
    printJson(payload);
    return doctorExitCode;
  }

  logger.header('flutter_shadcn doctor');

  void kv(String label, String value) {
    const pad = 22;
    final padded = label.padRight(pad);
    logger.info('  $padded $value');
  }

  print('');
  logger.section('Environment');
  kv('Script', Platform.script.toFilePath());
  kv('CWD', Directory.current.path);
  kv('PUB_CACHE', pubCache);

  print('');
  logger.section('Registry');
  kv('Mode', selection.mode);
  kv('Root', selection.registryRoot.root);
  kv('components.json', componentsSource);
  kv('Cache', cachePath ?? '(local registry, no cache)');
  kv('Schema', schemaSource?.label ?? '(not found)');

  print('');
  logger.section('Configuration');
  kv('SHADCN_REGISTRY_ROOT', envRoot ?? '(unset)');
  kv('SHADCN_REGISTRY_URL', envUrl ?? '(unset)');
  kv('cliRoot', roots.cliRoot ?? '(unresolved)');
  kv('localRegistryRoot', roots.localRegistryRoot ?? '(unresolved)');
  kv('config.registryMode', config.registryMode ?? '(unset)');
  kv('config.registryPath', config.registryPath ?? '(unset)');
  kv('config.registryUrl', config.registryUrl ?? '(unset)');

  print('');
  logger.section('Config paths');
  kv('installPath', resolvedInstallPath);
  kv('sharedPath', resolvedSharedPath);
  logger.info('  installPath valid: ${installPathValid ? 'yes' : 'no'}');
  logger.info('  sharedPath valid: ${sharedPathValid ? 'yes' : 'no'}');
  logger.info('  installPath exists: ${installPathExists ? 'yes' : 'no'}');
  logger.info('  sharedPath exists: ${sharedPathExists ? 'yes' : 'no'}');
  if (invalidAliases.isNotEmpty) {
    logger.warn('  invalid aliases: ${invalidAliases.join(', ')}');
  }

  print('');
  logger.section('Theme files');
  kv('color_scheme.dart', colorSchemeExists ? colorSchemePath : 'missing');

  print('');
  logger.section('Schema validation');
  if (schemaSource == null || registryData == null) {
    logger.warn('  Schema file not found.');
  } else if (schemaValid == true) {
    logger.success('  components.json matches the schema.');
  } else {
    logger.error('  Schema issues: ${schemaErrors.length}');
    for (final error in schemaErrors.take(12)) {
      logger.info('  - $error');
    }
    if (schemaErrors.length > 12) {
      logger.info('  ...and ${schemaErrors.length - 12} more');
    }
  }

  print('');
  logger.section('Lockfile');
  kv('shadcn.lock', lockfileExists ? 'present' : 'not present');
  kv('lockfileVersion', lock.lockfileVersion.toString());
  kv('locked components', lock.components.length.toString());
  if (missingLockedFiles.isEmpty) {
    if (lockfileError == null) {
      logger.success('  locked files are present.');
    } else {
      logger.error('  failed to parse shadcn.lock: $lockfileError');
    }
  } else {
    logger.error('  missing locked files: ${missingLockedFiles.length}');
    for (final file in missingLockedFiles.take(12)) {
      logger.info('  - $file');
    }
    if (missingLockedFiles.length > 12) {
      logger.info('  ...and ${missingLockedFiles.length - 12} more');
    }
  }

  print('');
  logger.section('Platform targets');
  logger
      .info('  (set .shadcn/config.json "platformTargets" to override paths)');
  platformTargets.forEach((platform, targets) {
    logger.info('  $platform:');
    for (final entry in targets.entries) {
      logger.info('    ${entry.key}: ${entry.value}');
    }
  });

  return doctorExitCode;
}
