import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/services/reset/reset_snapshot_store.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/bootstrap_dispatcher_builder.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/docs_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/runtime_roots.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/usage.dart';
import 'package:flutter_shadcn_cli/src/version_manager.dart';
import 'package:path/path.dart' as p;

/// The v2 CLI entry point (P5_CLI_PLAN.md §2).
///
/// Parses arguments, handles `--help`/`--version`/`docs`, then dispatches to a
/// command. Each registry-backed command resolves its own
/// [CommandContext] so a help request never touches the registry.
Future<void> runCliBootstrap(List<String> arguments) async {
  _ensureExecutablePath();
  final homeDirectory = _userHomeDirectory();
  if (homeDirectory != null && homeDirectory.isNotEmpty) {
    try {
      await ResetSnapshotStore(
        homeDirectory: homeDirectory,
      ).pruneExpiredSnapshots();
    } catch (_) {}
  }

  final parser = buildCliParser();
  final normalizedArgs = normalizeCliArgs(arguments);
  ArgResults argResults;
  try {
    argResults = parser.parse(normalizedArgs);
  } catch (e) {
    stderr.writeln('Error: $e');
    exit(ExitCodes.usage);
  }

  final advanced = argResults['advanced'] == true;
  if (argResults['help'] == true) {
    printCliUsage(advanced: advanced);
    exit(ExitCodes.success);
  }
  if (argResults['version'] == true) {
    VersionManager(
      logger: CliLogger(verbose: argResults['verbose'] == true),
    ).showVersion();
    exit(ExitCodes.success);
  }
  if (_isProjectHelpArgs(normalizedArgs)) {
    _printProjectUsage();
    exit(ExitCodes.success);
  }

  final command = argResults.command;
  if (command == null) {
    printCliUsage(advanced: advanced);
    exit(ExitCodes.usage);
  }

  if (!advanced && command.name == 'docs') {
    stderr.writeln('Error: The docs command requires --advanced.');
    exit(ExitCodes.usage);
  }

  final targetDir = Directory.current.path;
  final logger = CliLogger(verbose: argResults['verbose'] == true);
  final offline = argResults['offline'] == true;
  var config = await ShadcnConfig.load(targetDir);

  if (command.name == 'docs') {
    final roots = await resolveRoots();
    final cliRoot = roots.cliRoot ?? await packageRoot();
    final docsExit = await runDocsCommand(
      command: command,
      cliRoot: cliRoot,
      logger: logger,
    );
    if (docsExit == ExitCodes.ioError) {
      stderr.writeln('Error: Unable to resolve CLI root.');
    }
    if (docsExit != ExitCodes.success) {
      exitCode = docsExit;
    }
    return;
  }

  final dispatcher = buildBootstrapCommandDispatcher(
    rootArgs: argResults,
    command: command,
    targetDir: targetDir,
    homeDirectory: homeDirectory,
    offline: offline,
    logger: logger,
    readConfig: () => config,
    writeConfig: (updated) => config = updated,
  );
  final dispatchExit = await dispatcher.dispatch(command.name!);
  if (dispatchExit != ExitCodes.success) {
    exitCode = dispatchExit;
  }
}

void _ensureExecutablePath() {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    return;
  }
  final pubBin = p.join(home, '.pub-cache', 'bin');
  final pathEntries = (Platform.environment['PATH'] ?? '').split(':');
  if (pathEntries.contains(pubBin)) {
    return;
  }
  final target = p.join(pubBin, 'flutter_shadcn');
  final linkPath = '/usr/local/bin/flutter_shadcn';
  if (!File(target).existsSync()) {
    return;
  }
  final link = Link(linkPath);
  try {
    if (link.existsSync()) {
      return;
    }
    link.createSync(target);
  } catch (_) {
    return;
  }
}

String? _userHomeDirectory() {
  final env = Platform.environment;
  if (Platform.isWindows) {
    return env['USERPROFILE'] ?? env['HOME'];
  }
  return env['HOME'];
}

bool _isProjectHelpArgs(List<String> arguments) {
  if (arguments.length != 2 || arguments.first != 'project') {
    return false;
  }
  return arguments[1] == '--help' || arguments[1] == '-h';
}

void _printProjectUsage() {
  print('Usage: flutter_shadcn project <command>');
  print('');
  print('Commands:');
  print(
      '  reset [--undo]     Remove CLI-managed project files or restore them');
  print('  refresh            Re-apply the installed closure and theme');
}
