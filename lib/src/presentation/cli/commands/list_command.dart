import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_context.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_support.dart';

/// `flutter_shadcn list [--json]`: every component in the registry manifest
/// (P5_CLI_PLAN.md §2).
Future<int> runListCommand({
  required ArgResults listCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(listCommand, 'json');
  final logger = commandLogger(rootArgs, json: json);

  if (commandFlag(listCommand, 'help')) {
    stdout.writeln('Usage: flutter_shadcn list [--json]');
    stdout.writeln('');
    stdout.writeln('Lists every component from the registry manifest.');
    return ExitCodes.success;
  }

  try {
    final context = await CommandContextResolver.resolve(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    final components = context.loadedManifest.manifest.components.values
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    if (json) {
      printJson(jsonEnvelope(
        command: 'list',
        data: {
          'registry': context.loadedManifest.manifest.registry.name,
          'count': components.length,
          'components': [
            for (final component in components)
              {
                'id': component.id,
                'name': component.name,
                'category': component.category,
                'description': component.description,
                'tags': component.tags,
              },
          ],
        },
        meta: {'exitCode': ExitCodes.success},
      ));
      return ExitCodes.success;
    }
    if (components.isEmpty) {
      stdout.writeln('No components in this registry.');
      return ExitCodes.success;
    }
    stdout.writeln('Components (${components.length}):');
    for (final component in components) {
      stdout.writeln('  ${component.id.padRight(28)} ${component.description}');
    }
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}
