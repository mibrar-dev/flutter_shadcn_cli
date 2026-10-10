import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_context.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_support.dart';

/// `flutter_shadcn dry-run <ids…> [--all] [--json]`: a thin alias of
/// `add --dry-run` (P5_CLI_PLAN.md §2).
Future<int> runDryRunCommand({
  required ArgResults dryRunCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(dryRunCommand, 'json');
  final logger = commandLogger(rootArgs, json: json);

  if (commandFlag(dryRunCommand, 'help')) {
    stdout.writeln('Usage: flutter_shadcn dry-run <component|block...> '
        '[--json]');
    stdout.writeln('       flutter_shadcn dry-run --all [--blocks] [--json]');
    stdout.writeln('');
    stdout.writeln('Shows what `add` would write, without writing anything.');
    return ExitCodes.success;
  }

  final includeAll = commandFlag(dryRunCommand, 'all');
  final includeBlocks = commandFlag(dryRunCommand, 'blocks');
  final requested = componentIdsFrom(dryRunCommand);
  if (!includeAll && requested.isEmpty) {
    stdout
        .writeln('Usage: flutter_shadcn dry-run <component|block...> [--all]');
    return ExitCodes.usage;
  }

  try {
    final context = await CommandContextResolver.resolve(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    final manifest = context.loadedManifest.manifest;
    final ids =
        includeAll ? (manifest.components.keys.toList()..sort()) : requested;
    final plan = await context.installer.plan(
      ids,
      blockIds: includeAll && includeBlocks ? manifest.blocks.keys : const [],
      includeCore: true,
    );
    if (json) {
      printJson(jsonEnvelope(
        command: 'dry-run',
        data: plan.toJson(),
        meta: {'exitCode': ExitCodes.success},
      ));
    } else {
      plan.writeHuman(logger);
    }
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}
