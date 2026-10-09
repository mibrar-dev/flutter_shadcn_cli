import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_context.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_support.dart';

/// `flutter_shadcn add` with component ids [--dry-run] [--json] [--force] [--all]
/// [--include-preview]` (P5_CLI_PLAN.md §2.2).
///
/// Resolves the transitive closure, applies the single-owner preflight, copies
/// the files verbatim and refreshes `shadcn.lock` v2. User-owned
/// `<name>_theme.dart` files are never overwritten.
Future<int> runAddCommand({
  required ArgResults addCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(addCommand, 'json');
  final dryRun = commandFlag(addCommand, 'dry-run');
  final logger = commandLogger(rootArgs, json: json);

  if (commandFlag(addCommand, 'help')) {
    _printAddHelp();
    return ExitCodes.success;
  }

  final includeAll = commandFlag(addCommand, 'all');
  final force = commandFlag(addCommand, 'force');
  final includePreview = commandFlag(addCommand, 'include-preview');
  final requested = componentIdsFrom(addCommand);
  if (!includeAll && requested.isEmpty) {
    _printAddHelp();
    return ExitCodes.usage;
  }

  try {
    final context = await CommandContextResolver.resolve(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    final ids = includeAll
        ? (context.loadedManifest.manifest.components.keys.toList()..sort())
        : requested;

    final report = await context.installer.add(
      ids,
      dryRun: dryRun,
      includePreview: includePreview,
      overwrite: force,
      includeCore: true,
    );

    if (json) {
      printJson(jsonEnvelope(
        command: 'add',
        data: report.toJson(),
        meta: {'exitCode': ExitCodes.success},
      ));
    } else if (!report.applied) {
      report.plan.writeHuman(logger);
    } else {
      report.writeHuman(logger);
    }
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}

void _printAddHelp() {
  stdout.writeln('Usage: flutter_shadcn add <component...> [flags]');
  stdout.writeln('       flutter_shadcn add --all [flags]');
  stdout.writeln('');
  stdout
      .writeln('Installs the transitive closure of the requested components:');
  stdout.writeln(
      'components, primitives, and the always-on foundation/theme core.');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout
      .writeln('  --all               Install every component in the registry');
  stdout
      .writeln('  --dry-run           Print the plan without writing anything');
  stdout.writeln(
      '  --force             Overwrite locally modified registry files');
  stdout.writeln('  --include-preview   Also copy each component preview.dart');
  stdout.writeln('  --json              Machine-readable output on stdout');
  stdout.writeln('  --help, -h          Show this message');
}
