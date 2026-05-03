import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/services/reset/global_reset_service.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';

typedef ResetConfirmationReader = String? Function();

Future<int> runResetCommand({
  required ArgResults command,
  required GlobalResetService service,
  ResetConfirmationReader? readConfirmation,
}) async {
  if (command['help'] == true) {
    print('Usage: flutter_shadcn reset');
    print('');
    print('Delete global CLI-managed cache and state under ~/.flutter_shadcn.');
    print('This does not remove project files or uninstall the executable.');
    return ExitCodes.success;
  }

  final reader = readConfirmation ?? stdin.readLineSync;
  stdout.write(
    'This will delete global flutter_shadcn state under ~/.flutter_shadcn. Continue? [y/N]: ',
  );
  final input = reader()?.trim().toLowerCase();
  if (input != 'y' && input != 'yes') {
    print('Cancelled.');
    return ExitCodes.success;
  }

  final result = await service.reset();
  if (result.deletedRelativePaths.isEmpty) {
    print('No global CLI state found.');
    return ExitCodes.success;
  }

  print('Deleted global CLI state:');
  for (final relativePath in result.deletedRelativePaths) {
    print('  - ~/.flutter_shadcn/$relativePath');
  }
  return ExitCodes.success;
}
