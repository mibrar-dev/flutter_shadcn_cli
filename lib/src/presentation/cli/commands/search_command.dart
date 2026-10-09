import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_context.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_support.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_component.dart';

/// `flutter_shadcn search <query> [--json]`: case-insensitive match over
/// component id, name, description and tags (P5_CLI_PLAN.md §2).
Future<int> runSearchCommand({
  required ArgResults searchCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(searchCommand, 'json');
  final logger = commandLogger(rootArgs, json: json);

  if (commandFlag(searchCommand, 'help')) {
    stdout.writeln('Usage: flutter_shadcn search <query> [--json]');
    stdout.writeln('');
    stdout.writeln('Searches component id, name, description and tags.');
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
    final matches = context.loadedManifest.manifest.components.values
        .where((component) => _matches(component, query))
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    if (json) {
      printJson(jsonEnvelope(
        command: 'search',
        data: {
          'query': query,
          'count': matches.length,
          'components': [
            for (final component in matches)
              {
                'id': component.id,
                'name': component.name,
                'description': component.description,
                'tags': component.tags,
              },
          ],
        },
        meta: {'exitCode': ExitCodes.success},
      ));
      return ExitCodes.success;
    }
    if (matches.isEmpty) {
      stdout.writeln('No components match "$query".');
      return ExitCodes.success;
    }
    stdout.writeln('${matches.length} match(es) for "$query":');
    for (final component in matches) {
      stdout.writeln('  ${component.id.padRight(28)} ${component.description}');
    }
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}

bool _matches(ManifestComponent component, String query) {
  if (component.id.toLowerCase().contains(query) ||
      component.name.toLowerCase().contains(query) ||
      component.description.toLowerCase().contains(query)) {
    return true;
  }
  for (final tag in component.tags) {
    if (tag.toLowerCase().contains(query)) {
      return true;
    }
  }
  return false;
}
