import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_context.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_support.dart';

/// `flutter_shadcn add` with component and block ids
/// `[--dry-run] [--json] [--force] [--all] [--blocks] [--include-preview]`
/// (P5_CLI_PLAN.md §2.2, P6-B2).
///
/// Resolves the transitive closure of every requested id — a component *or* a
/// block — applies the single-owner preflight, copies the files verbatim and
/// refreshes `shadcn.lock` v2. A block lands in `blocks/<id>/` together with
/// every component, primitive, theme and foundation unit it needs.
/// User-owned `<name>_theme.dart` files are never overwritten.
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
  final includeBlocks = commandFlag(addCommand, 'blocks');
  final force = commandFlag(addCommand, 'force');
  final includePreview = commandFlag(addCommand, 'include-preview');
  final requested = componentIdsFrom(addCommand);
  if (!includeAll && requested.isEmpty) {
    _printAddHelp();
    return ExitCodes.usage;
  }
  if (includeBlocks && !includeAll) {
    logger.warn('--blocks only widens --all; it does nothing on its own.');
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

    final report = await context.installer.add(
      ids,
      blockIds: includeAll && includeBlocks ? manifest.blocks.keys : const [],
      dryRun: dryRun,
      includePreview: includePreview,
      overwrite: force,
      includeCore: true,
      includeAllPrimitives: includeAll,
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
  stdout.writeln('Usage: flutter_shadcn add <component|block...> [flags]');
  stdout.writeln('       flutter_shadcn add --all [--blocks] [flags]');
  stdout.writeln('');
  stdout.writeln('Installs the transitive closure of every requested id:');
  stdout.writeln(
      'components, blocks, primitives, and the always-on foundation/theme '
      'core.');
  stdout.writeln('A block installs to blocks/<id>/ with the components it '
      'uses.');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout
      .writeln('  --all               Install every component in the registry');
  stdout.writeln('  --blocks            With --all, install every block too');
  stdout
      .writeln('  --dry-run           Print the plan without writing anything');
  stdout.writeln(
      '  --force             Overwrite locally modified registry files');
  stdout.writeln('  --include-preview   Also copy each component preview.dart');
  stdout.writeln('  --json              Machine-readable output on stdout');
  stdout.writeln('  --help, -h          Show this message');
}
