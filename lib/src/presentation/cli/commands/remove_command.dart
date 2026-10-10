import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_context.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_support.dart';

/// `flutter_shadcn remove [ids…] [--all] [--force] [--purge-user-themes]
/// [--json]` (P5_CLI_PLAN.md §2, P6-B2).
///
/// Deletes registry-owned files, prunes orphaned layer units, and refuses when
/// another installed component or block still needs the target (unless
/// `--force`). User-owned `<name>_theme.dart` files are kept unless
/// `--purge-user-themes`; a block owns none.
Future<int> runRemoveCommand({
  required ArgResults removeCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(removeCommand, 'json');
  final logger = commandLogger(rootArgs, json: json);

  if (commandFlag(removeCommand, 'help')) {
    stdout.writeln('Usage: flutter_shadcn remove <component|block...> '
        '[flags]');
    stdout.writeln('       flutter_shadcn remove --all [flags]');
    stdout.writeln('');
    stdout.writeln('Options:');
    stdout.writeln('  --all                 Remove every installed component '
        'and block');
    stdout.writeln('  --force               Remove even if dependents remain');
    stdout.writeln(
        '  --purge-user-themes   Also delete <name>_theme.dart user files');
    stdout.writeln('  --json                Machine-readable output on stdout');
    return ExitCodes.success;
  }

  final removeAll = commandFlag(removeCommand, 'all');
  final force = commandFlag(removeCommand, 'force');
  final purgeUserThemes = commandFlag(removeCommand, 'purge-user-themes');
  var ids = componentIdsFrom(removeCommand);
  if (!removeAll && ids.isEmpty) {
    stdout.writeln('Usage: flutter_shadcn remove <component|block...> [--all]');
    return ExitCodes.usage;
  }

  try {
    final context = await CommandContextResolver.resolve(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    if (removeAll) {
      final lock = await ShadcnLockRepository(projectRoot).load();
      ids = [...lock.componentIds, ...lock.blockIds];
    }
    final report = await context.installer.remove(
      ids,
      force: force,
      purgeUserThemes: purgeUserThemes,
    );
    if (json) {
      printJson(jsonEnvelope(
        command: 'remove',
        data: report.toJson(),
        meta: {'exitCode': ExitCodes.success},
      ));
    } else {
      report.writeHuman(logger);
    }
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}
