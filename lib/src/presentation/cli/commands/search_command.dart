import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/catalog_entry.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_context.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_support.dart';

/// `flutter_shadcn search <query> [--category <c>] [--json]`:
/// case-insensitive match over component and block id, name, description and
/// tags (P5_CLI_PLAN.md §2, P6-B2).
///
/// Both kinds are searched at once, because `add <id>` resolves both: a query
/// that names a block is exactly as useful as one that names a component.
Future<int> runSearchCommand({
  required ArgResults searchCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(searchCommand, 'json');
  final category = commandOption(searchCommand, 'category');
  final logger = commandLogger(rootArgs, json: json);

  if (commandFlag(searchCommand, 'help')) {
    stdout.writeln('Usage: flutter_shadcn search <query> '
        '[--category <c>] [--json]');
    stdout.writeln('');
    stdout.writeln('Searches component and block id, name, description and '
        'tags.');
    stdout.writeln('');
    stdout.writeln('Options:');
    stdout.writeln('  --category <name>  Only entries of that category');
    stdout.writeln('  --json             Machine-readable output on stdout');
    return ExitCodes.success;
  }

  final query = searchCommand.rest.join(' ').trim().toLowerCase();
  if (query.isEmpty) {
    stdout.writeln('Usage: flutter_shadcn search <query>');
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
    final matches = filterByCategory(
      [
        for (final component in manifest.components.values)
          if (CatalogEntry.component(component).matches(query))
            CatalogEntry.component(component),
        for (final block in manifest.blocks.values)
          if (CatalogEntry.block(block).matches(query))
            CatalogEntry.block(block),
      ],
      category,
    )..sort((a, b) => a.id.compareTo(b.id));

    if (json) {
      printJson(jsonEnvelope(
        command: 'search',
        data: {
          'query': query,
          'count': matches.length,
          'categories': categorySummary(matches),
          'components': [
            for (final match in matches)
              if (match.kind == CatalogKind.component) match.toJson(),
          ],
          'blocks': [
            for (final match in matches)
              if (match.kind == CatalogKind.block) match.toJson(),
          ],
        },
        meta: {'exitCode': ExitCodes.success},
      ));
      return ExitCodes.success;
    }
    if (matches.isEmpty) {
      final wanted = category?.trim();
      final scope =
          wanted == null || wanted.isEmpty ? '' : ' in category "$wanted"';
      stdout.writeln('No components or blocks match "$query"$scope.');
      return ExitCodes.success;
    }
    stdout.writeln('${matches.length} match(es) for "$query":');
    for (final match in matches) {
      final label = match.kind == CatalogKind.block ? 'block' : 'component';
      stdout.writeln('  ${match.id.padRight(28)} [${match.category} · $label] '
          '${match.description}');
    }
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}
