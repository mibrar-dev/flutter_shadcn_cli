import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';

/// `audit`: installed-vs-lock drift (P5_CLI_PLAN.md §2). Exit `50`
/// (`validationFailed`) when any registry-owned file is modified or missing.
Future<int> runAuditCommand({
  required String projectRoot,
  required String? manifestSha256,
  required bool jsonOutput,
  required CliLogger logger,
}) async {
  final lockRepo = ShadcnLockRepository(projectRoot);
  if (!lockRepo.existsSync()) {
    if (jsonOutput) {
      printJson(jsonEnvelope(
        command: 'audit',
        data: const {'installed': false},
        meta: {'exitCode': ExitCodes.success},
      ));
    } else {
      logger.info('No shadcn.lock found; nothing installed.');
    }
    return ExitCodes.success;
  }

  final lock = await lockRepo.load();
  final drift = await lockRepo.inspect(lock, manifestSha256: manifestSha256);
  final exitCode = drift.registryOwnedDrift.isEmpty
      ? ExitCodes.success
      : ExitCodes.validationFailed;

  if (jsonOutput) {
    printJson(jsonEnvelope(
      command: 'audit',
      data: {
        'components': lock.componentIds,
        'blocks': lock.blockIds,
        'drift': drift.toJson(),
      },
      meta: {'exitCode': exitCode},
    ));
    return exitCode;
  }

  logger.header('Install audit');
  logger.info('Installed components: ${lock.componentIds.length}');
  if (lock.blocks.isNotEmpty) {
    logger.info('Installed blocks: ${lock.blockIds.length}');
  }
  if (drift.registryOwnedDrift.isEmpty) {
    logger.success('All registry-owned files match shadcn.lock.');
  } else {
    logger.error('${drift.registryOwnedDrift.length} file(s) drifted:');
    for (final file in drift.registryOwnedDrift.take(12)) {
      logger.info('  - ${file.path} (${file.status.name})');
    }
  }
  if (drift.userOwnedDrift.isNotEmpty) {
    logger.warn('${drift.userOwnedDrift.length} user-owned file(s) modified.');
  }
  return exitCode;
}
