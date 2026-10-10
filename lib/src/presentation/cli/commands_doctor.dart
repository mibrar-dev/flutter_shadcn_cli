import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_file_install_part.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/application/services/manifest_closure.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_manifest_loader.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_context.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_support.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Doctor exit codes (plan §2.5).
class DoctorExit {
  static const int clean = 0;
  static const int drift = 1;
  static const int brokenClosure = 2;
  static const int manifestInvalid = 3;
}

/// `flutter_shadcn doctor [--json]` (P5_CLI_PLAN.md §2.5).
///
/// Checks the manifest, the installed closure, the layer layout, per-file lock
/// drift, user-owned files, the pubspec SDK deps and the import-depth guard.
Future<int> runDoctorCommand({
  required ArgResults doctorCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(doctorCommand, 'json');
  final logger = commandLogger(rootArgs, json: json);

  if (commandFlag(doctorCommand, 'help')) {
    stdout.writeln('Usage: flutter_shadcn doctor [--json]');
    stdout.writeln('');
    stdout
        .writeln('Diagnoses the registry manifest and the installed project.');
    return ExitCodes.success;
  }

  final CommandContext context;
  try {
    context = await CommandContextResolver.resolve(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
  } on RegistryManifestException catch (error) {
    if (json) {
      printJson(jsonEnvelope(
        command: 'doctor',
        data: const {},
        errors: [
          jsonError(
            code: ExitCodeLabels.schemaInvalid,
            message: error.message,
            details: {'issues': error.details},
          ),
        ],
        meta: {'exitCode': DoctorExit.manifestInvalid},
      ));
    } else {
      logger.errorToStderr('Error: ${error.message}');
      for (final line in error.details) {
        logger.errorToStderr('  - $line');
      }
    }
    return DoctorExit.manifestInvalid;
  } catch (error) {
    return reportCommandError(error, logger);
  }

  final report = await _Diagnosis.run(context);
  final exitCode = report.exitCode;

  if (json) {
    printJson(jsonEnvelope(
      command: 'doctor',
      data: report.toJson(),
      errors: [
        for (final issue in report.errors)
          jsonError(code: issue.code, message: issue.message),
      ],
      warnings: [
        for (final issue in report.warnings)
          jsonWarning(code: issue.code, message: issue.message),
      ],
      meta: {'exitCode': exitCode},
    ));
    return exitCode;
  }

  logger.header('flutter_shadcn doctor');
  logger.section('Registry');
  logger.info('  root:     ${context.source.describe('')}');
  logger.info('  manifest: ${context.loadedManifest.path} '
      '(sha ${context.loadedManifest.sha256.substring(0, 12)})');
  logger.info('  install:  ${context.installRoot}');
  logger.section('Installed');
  logger.info('  components: ${report.installedComponents}');
  logger.info('  files:      ${report.trackedFiles} '
      '(${report.modifiedFiles} modified, ${report.missingFiles} missing)');
  if (report.errors.isEmpty && report.warnings.isEmpty) {
    logger.success('No issues found.');
  }
  for (final issue in report.errors) {
    logger.error(issue.message);
  }
  for (final issue in report.warnings) {
    logger.warn(issue.message);
  }
  return exitCode;
}

class _Issue {
  const _Issue(this.code, this.message);

  final String code;
  final String message;
}

class _Diagnosis {
  _Diagnosis();

  final List<_Issue> errors = [];
  final List<_Issue> warnings = [];

  int installedComponents = 0;
  int trackedFiles = 0;
  int modifiedFiles = 0;
  int missingFiles = 0;

  int get exitCode {
    if (errors.any((issue) => issue.code == _brokenClosureCode)) {
      return DoctorExit.brokenClosure;
    }
    if (errors.isNotEmpty) {
      return DoctorExit.drift;
    }
    return DoctorExit.clean;
  }

  static const String _brokenClosureCode = 'broken_closure';

  Map<String, dynamic> toJson() => {
        'installedComponents': installedComponents,
        'trackedFiles': trackedFiles,
        'modifiedFiles': modifiedFiles,
        'missingFiles': missingFiles,
        'errors': [
          for (final issue in errors)
            {'code': issue.code, 'message': issue.message},
        ],
        'warnings': [
          for (final issue in warnings)
            {'code': issue.code, 'message': issue.message},
        ],
      };

  static Future<_Diagnosis> run(CommandContext context) async {
    final diagnosis = _Diagnosis();
    final manifest = context.loadedManifest.manifest;
    final lockRepo = ShadcnLockRepository(context.projectRoot);
    final lock = await lockRepo.load();
    diagnosis.installedComponents = lock.components.length;

    // Layer layout at the right depth (plan §3). `init` always creates
    // foundation/ and theme/; `primitives/` and `components/` appear only when
    // something is installed there, and the closure check below proves those
    // directories (and every needed file) exist.
    for (final dir in const ['foundation', 'theme']) {
      final path = p.join(context.projectRoot, context.installRoot, dir);
      if (!Directory(path).existsSync()) {
        diagnosis.errors.add(_Issue(
          _brokenClosureCode,
          'Missing layer directory: ${context.installRoot}/$dir',
        ));
      }
    }

    // Closure present: every file the installed closure needs exists on disk.
    final closure = ManifestClosureResolver(manifest).resolve(
      lock.componentIds,
      blockIds: lock.blockIds,
      includeCore: true,
    );
    final missing = <String>[];
    for (final source in closure.files) {
      final target = p.posix.join(context.installRoot, source);
      if (!File(p.join(context.projectRoot, target)).existsSync()) {
        missing.add(target);
      }
    }
    if (missing.isNotEmpty) {
      diagnosis.errors.add(_Issue(
        _brokenClosureCode,
        'Installed closure is incomplete (${missing.length} file(s) missing).',
      ));
    }

    // Lock drift.
    final drift = await lockRepo.inspect(
      lock,
      manifestSha256: context.loadedManifest.sha256,
    );
    diagnosis.trackedFiles = drift.files.length;
    diagnosis.modifiedFiles = drift.modified.length;
    diagnosis.missingFiles = drift.missing.length;
    for (final file in drift.registryOwnedDrift) {
      diagnosis.errors.add(_Issue(
        'drift',
        '${file.path} is ${file.status.name} (registry-owned).',
      ));
    }
    for (final file in drift.userOwnedDrift) {
      diagnosis.warnings.add(_Issue(
        'user_owned_drift',
        '${file.path} is ${file.status.name} (user-owned).',
      ));
    }
    if (drift.registryMoved) {
      diagnosis.warnings.add(_Issue(
        'registry_moved',
        'The registry manifest changed since this install; run `update`.',
      ));
    }

    // Import-depth guard on installed component and block files.
    final guard = InstallerFileInstaller(
      projectRoot: context.projectRoot,
      installRoot: context.installRoot,
      reader: const _NoopReader(),
    );
    final contents = <String, String>{};
    for (final component in lock.components) {
      for (final target in component.files.keys) {
        final file = File(p.join(context.projectRoot, target));
        if (await file.exists()) {
          final prefix = '${context.installRoot}/';
          final source = target.startsWith(prefix)
              ? target.substring(prefix.length)
              : target;
          contents[source] = await file.readAsString();
        }
      }
    }
    for (final block in lock.blocks) {
      for (final target in block.files.keys) {
        final file = File(p.join(context.projectRoot, target));
        if (await file.exists()) {
          final prefix = '${context.installRoot}/';
          final source = target.startsWith(prefix)
              ? target.substring(prefix.length)
              : target;
          contents[source] = await file.readAsString();
        }
      }
    }
    try {
      guard.assertImportGuard(contents);
    } on ImportGuardException catch (error) {
      diagnosis.errors.add(_Issue(_brokenClosureCode, error.toString()));
    }

    // Pubspec SDK deps the closure declares.
    await _checkPubspec(context, closure, diagnosis);
    return diagnosis;
  }

  static Future<void> _checkPubspec(
    CommandContext context,
    ManifestClosure closure,
    _Diagnosis diagnosis,
  ) async {
    final pubspec = File(p.join(context.projectRoot, 'pubspec.yaml'));
    if (!await pubspec.exists()) {
      diagnosis.warnings.add(const _Issue(
        'pubspec_missing',
        'pubspec.yaml not found; cannot verify dependencies.',
      ));
      return;
    }
    final dependencies = _dependencies(await pubspec.readAsString());
    final missing = <String>[];
    for (final package in closure.packages) {
      if (package.name.isEmpty) {
        continue;
      }
      if (!dependencies.contains(package.name)) {
        missing.add(package.name);
      }
    }
    if (missing.isNotEmpty) {
      diagnosis.warnings.add(_Issue(
        'pubspec_missing_deps',
        'pubspec.yaml is missing: ${missing.join(', ')}',
      ));
    }
  }

  static Set<String> _dependencies(String pubspec) {
    final names = <String>{};
    try {
      final doc = loadYaml(pubspec);
      if (doc is YamlMap) {
        for (final section in const ['dependencies', 'dev_dependencies']) {
          final deps = doc[section];
          if (deps is YamlMap) {
            for (final key in deps.keys) {
              names.add(key.toString());
            }
          }
        }
      }
    } catch (_) {
      // A malformed pubspec is reported by the missing-deps warning.
    }
    return names;
  }
}

/// Doctor never reads from the registry source during the import guard.
class _NoopReader implements RegistryFileReader {
  const _NoopReader();

  @override
  Future<List<int>?> readBytes(String relPath) async => null;

  @override
  Future<String?> readString(String relPath) async => null;
}
