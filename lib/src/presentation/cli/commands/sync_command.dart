import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/installer.dart';

Future<int> runSyncCommand({
  required ArgResults command,
  required Installer? installer,
}) async {
  if (command['help'] == true) {
    print('Usage: flutter_shadcn sync');
    print('');
    print('Re-applies .shadcn/config.json (paths, theme) to existing files.');
    return ExitCodes.success;
  }
  final activeInstaller = installer;
  if (activeInstaller == null) {
    stderr.writeln('Error: Installer is not available.');
    return ExitCodes.registryNotFound;
  }
  await activeInstaller.syncFromConfig();
  return ExitCodes.success;
}
