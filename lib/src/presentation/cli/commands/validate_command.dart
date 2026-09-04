import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:flutter_shadcn_cli/src/validate_command.dart'
    as validate_service;

Future<int> runValidateCommandCli({
  required ArgResults command,
  required Registry? registry,
  required bool offline,
  required CliLogger logger,
}) async {
  if (command['help'] == true) {
    print('Usage: flutter_shadcn validate [--json]');
    print('');
    print('Validates components.json and registry file dependencies.');
    print('Options:');
    print('  --json             Output machine-readable JSON');
    return ExitCodes.success;
  }
  if (registry == null) {
    // Mirror doctor --json: emit a parseable envelope instead of
    // stderr-only text (previously exit 20 with NO JSON).
    if (command['json'] == true) {
      final offlineUnavailable = offline;
      final code = offlineUnavailable
          ? ExitCodes.offlineUnavailable
          : ExitCodes.registryNotFound;
      printJson(jsonEnvelope(
        command: 'validate',
        data: const {},
        errors: [
          jsonError(
            code: offlineUnavailable
                ? ExitCodeLabels.offlineUnavailable
                : ExitCodeLabels.registryNotFound,
            message: offlineUnavailable
                ? 'Offline mode: cached components.json not found.'
                : 'Error: Registry is not available.',
          ),
        ],
        meta: {'exitCode': code},
      ));
      return code;
    }
    stderr.writeln('Error: Registry is not available.');
    return ExitCodes.registryNotFound;
  }
  return validate_service.runValidateCommand(
    registry: registry,
    registryRoot: registry.registryRoot,
    sourceRoot: registry.sourceRoot,
    offline: offline,
    jsonOutput: command['json'] == true,
    logger: logger,
  );
}
