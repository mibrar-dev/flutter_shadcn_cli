import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/catalog_entry.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_context.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_support.dart';

/// `flutter_shadcn list [--blocks] [--category <c>] [--json]`: every component
/// (default) or every block in the registry manifest, grouped by the category
/// P6-B1 stores in each `meta.json` (P5_CLI_PLAN.md §2, P6-B2).
///
/// The JSON envelope always carries both `components` and `blocks`: the one
/// that is not on show is an empty array, so a consumer never has to probe for
/// a key.
Future<int> runListCommand({
  required ArgResults listCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(listCommand, 'json');
  final showBlocks = commandFlag(listCommand, 'blocks');
  final category = commandOption(listCommand, 'category');
  final logger = commandLogger(rootArgs, json: json);

  if (commandFlag(listCommand, 'help')) {
    stdout.writeln('Usage: flutter_shadcn list [--blocks] [--category <c>] '
        '[--json]');
    stdout.writeln('');
    stdout
        .writeln('Lists components (default) or blocks, grouped by category.');
    stdout.writeln('');
    stdout.writeln('Options:');
    stdout.writeln('  --blocks           List the blocks layer instead');
    stdout.writeln('  --category <name>  Only entries of that category');
    stdout.writeln('  --json             Machine-readable output on stdout');
    return ExitCodes.success;
  }

  try {
    final context = await CommandContextResolver.resolve(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    final manifest = context.loadedManifest.manifest;
    final components = filterByCategory(
      [
        for (final component in manifest.components.values)
          CatalogEntry.component(component),
      ],
      category,
    )..sort((a, b) => a.id.compareTo(b.id));
    final blocks = filterByCategory(
      [
        for (final block in manifest.blocks.values) CatalogEntry.block(block),
      ],
      category,
    )..sort((a, b) => a.id.compareTo(b.id));
    final shown = showBlocks ? blocks : components;

    if (json) {
      printJson(jsonEnvelope(
        command: 'list',
        data: {
          'registry': manifest.registry.name,
          'kind':
              showBlocks ? CatalogKind.block.name : CatalogKind.component.name,
          'count': shown.length,
          'categories': categorySummary(shown),
          'components': showBlocks ? const [] : components,
          'blocks': showBlocks ? blocks : const [],
        },
        meta: {'exitCode': ExitCodes.success},
      ));
      return ExitCodes.success;
    }

    if (shown.isEmpty) {
      final wanted = category?.trim();
      if (wanted != null && wanted.isNotEmpty) {
        stdout.writeln('No ${showBlocks ? 'blocks' : 'components'} in category '
            '"$wanted".');
        // The two taxonomies are independent (13 component categories, 6 block
        // families), so an empty result is usually the wrong list.
        final other = showBlocks ? components : blocks;
        if (other.isNotEmpty) {
          stdout.writeln('Try `list${showBlocks ? '' : ' --blocks'}` for the '
              'other catalog.');
        }
      } else {
        stdout.writeln('No ${showBlocks ? 'blocks' : 'components'} in this '
            'registry.');
      }
      return ExitCodes.success;
    }
    stdout.writeln('${shown.length} ${showBlocks ? 'block' : 'component'}(s) '
        'by category:');
    writeGroupedCatalog(shown, write: stdout.writeln);
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}
