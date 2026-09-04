import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/services/reset/project_reset_service.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';

class ProjectRefreshOutput {
  final int regeneratedFiles;
  final List<String> repairedPaths;

  const ProjectRefreshOutput({
    required this.regeneratedFiles,
    this.repairedPaths = const [],
  });
}

typedef ProjectResetRunner = Future<ProjectResetResult> Function();
typedef ProjectResetUndoRunner = Future<ProjectResetUndoResult> Function();
typedef ProjectRefreshRunner = Future<ProjectRefreshOutput> Function();

Future<int> runProjectCommand({
  required ArgResults command,
  required ProjectResetRunner resetProject,
  required ProjectResetUndoRunner undoProject,
  required ProjectRefreshRunner refreshProject,
}) async {
  final restHelp =
      command.rest.contains('--help') || command.rest.contains('-h');
  if (command['help'] == true || restHelp || command.command == null) {
    _printProjectUsage();
    return command.command == null && !restHelp
        ? ExitCodes.usage
        : ExitCodes.success;
  }

  final nested = command.command!;
  switch (nested.name) {
    case 'reset':
      return _runProjectResetCommand(
        command: nested,
        resetProject: resetProject,
        undoProject: undoProject,
      );
    case 'refresh':
      return _runProjectRefreshCommand(
        command: nested,
        refreshProject: refreshProject,
      );
    default:
      _printProjectUsage();
      return ExitCodes.usage;
  }
}

Future<int> _runProjectResetCommand({
  required ArgResults command,
  required ProjectResetRunner resetProject,
  required ProjectResetUndoRunner undoProject,
}) async {
  if (command['help'] == true) {
    print('Usage: flutter_shadcn project reset [--undo]');
    print('');
    print('Remove CLI-managed project files and folders.');
    print('Use --undo within 24 hours to restore the latest reset snapshot.');
    return ExitCodes.success;
  }

  if (command['undo'] == true) {
    try {
      final result = await undoProject();
      print(
        'Restored project reset snapshot from ${result.snapshot.createdAtUtc.toIso8601String()}.',
      );
      return ExitCodes.success;
    } on StateError catch (error) {
      stderr.writeln('Error: ${error.message}');
      return ExitCodes.ioError;
    } catch (error) {
      stderr.writeln('Error: $error');
      return ExitCodes.ioError;
    }
  }

  final result = await resetProject();
  final deletedRoots = result.deletedDirectoryRoots;
  if (deletedRoots.isEmpty) {
    print('No CLI-managed project files found.');
    return ExitCodes.success;
  }

  print('Removed CLI-managed project files:');
  for (final root in deletedRoots) {
    print('  - $root');
  }
  print(
    'Undo available until ${result.snapshot.expiresAtUtc.toIso8601String()} via `flutter_shadcn project reset --undo`.',
  );
  return ExitCodes.success;
}

Future<int> _runProjectRefreshCommand({
  required ArgResults command,
  required ProjectRefreshRunner refreshProject,
}) async {
  if (command['help'] == true) {
    print('Usage: flutter_shadcn project refresh');
    print('');
    print(
        'Regenerate missing CLI scaffolding without overwriting existing files.');
    return ExitCodes.success;
  }

  final result = await refreshProject();
  if (result.regeneratedFiles == 0) {
    print('Project scaffolding is already complete.');
    return ExitCodes.success;
  }

  print('Regenerated ${result.regeneratedFiles} missing scaffolding files.');
  for (final path in result.repairedPaths) {
    print('  - $path');
  }
  return ExitCodes.success;
}

void _printProjectUsage() {
  print('Usage: flutter_shadcn project <command>');
  print('');
  print('Commands:');
  print(
      '  reset [--undo]     Remove CLI-managed project files or restore them');
  print('  refresh            Regenerate missing CLI scaffolding');
}
