import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/audit_command.dart' as audit_service;
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';

Future<int> runAuditCommandCli({
  required ArgResults command,
  required Registry? registry,
  required String targetDir,
  required ShadcnConfig config,
  String? registryNamespace,
  required CliLogger logger,
}) async {
  if (command['help'] == true) {
    print('Usage: flutter_shadcn audit [--json]');
    print('');
    print('Audits installed components against registry metadata.');
    print('Options:');
    print('  --json             Output machine-readable JSON');
    return ExitCodes.success;
  }
  if (registry == null) {
    stderr.writeln('Error: Registry is not available.');
    return ExitCodes.registryNotFound;
  }
  return audit_service.runAuditCommand(
    registry: registry,
    targetDir: targetDir,
    config: config,
    registryNamespace: registryNamespace,
    jsonOutput: command['json'] == true,
    logger: logger,
  );
}
