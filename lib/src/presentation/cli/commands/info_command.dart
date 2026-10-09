import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/services/manifest_closure.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_context.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_support.dart';

/// `flutter_shadcn info <component> [--json]`: dependency closure, files, api
/// and theme class for one component (P5_CLI_PLAN.md §2).
Future<int> runInfoCommand({
  required ArgResults infoCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(infoCommand, 'json');
  final logger = commandLogger(rootArgs, json: json);

  if (commandFlag(infoCommand, 'help')) {
    stdout.writeln('Usage: flutter_shadcn info <component> [--json]');
    stdout.writeln('');
    stdout
        .writeln('Shows the dependency closure, files and api of a component.');
    return ExitCodes.success;
  }

  final ids = componentIdsFrom(infoCommand);
  if (ids.isEmpty) {
    stdout.writeln('Usage: flutter_shadcn info <component>');
    return ExitCodes.usage;
  }
  if (ids.length > 1) {
    logger.errorToStderr(
      'Error: info accepts a single component id. Got ${ids.length}: '
      '${ids.join(', ')}.',
    );
    return ExitCodes.usage;
  }
  final id = ids.first;

  try {
    final context = await CommandContextResolver.resolve(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    final manifest = context.loadedManifest.manifest;
    final component = manifest.components[id];
    if (component == null) {
      if (json) {
        printJson(jsonEnvelope(
          command: 'info',
          data: {'id': id},
          errors: [
            jsonError(
              code: ExitCodeLabels.componentMissing,
              message: 'Component "$id" is not in the registry manifest.',
            ),
          ],
          meta: {'exitCode': ExitCodes.componentMissing},
        ));
      } else {
        logger.errorToStderr('Error: component "$id" is not in the registry.');
      }
      return ExitCodes.componentMissing;
    }

    final closure = ManifestClosureResolver(manifest).resolve([id]);
    final data = <String, dynamic>{
      'id': component.id,
      'name': component.name,
      'category': component.category,
      'description': component.description,
      'tags': component.tags,
      'entry': component.entry,
      'installRoot': context.installRoot,
      'import': _importPath(context.installRoot, component.entry),
      'files': component.files,
      'userOwned': component.userOwned,
      'deps': {
        'components': component.deps.components,
        'primitives': component.deps.primitives,
        'foundation': component.deps.foundation,
        'theme': component.deps.theme,
      },
      'closure': {
        'components': closure.components,
        'primitives': closure.primitives,
        'foundation': closure.foundation,
        'theme': closure.theme,
      },
      'api': component.api.groups,
      'themeClass': component.theme?.className,
    };

    if (json) {
      printJson(jsonEnvelope(
        command: 'info',
        data: data,
        meta: {'exitCode': ExitCodes.success},
      ));
      return ExitCodes.success;
    }

    stdout.writeln('${component.id} — ${component.name}');
    stdout.writeln('  category:    ${component.category}');
    stdout.writeln('  description: ${component.description}');
    if (component.tags.isNotEmpty) {
      stdout.writeln('  tags:        ${component.tags.join(', ')}');
    }
    stdout.writeln('  import:      ${data['import']}');
    if (component.theme?.className != null) {
      stdout.writeln('  theme class: ${component.theme!.className}');
    }
    stdout.writeln('');
    stdout.writeln('Dependencies (direct):');
    _printList('  components', component.deps.components);
    _printList('  primitives', component.deps.primitives);
    _printList('  foundation', component.deps.foundation);
    _printList('  theme', component.deps.theme);
    stdout.writeln('');
    stdout.writeln('Closure:');
    _printList('  components', closure.components);
    _printList('  primitives', closure.primitives);
    stdout.writeln('');
    stdout.writeln('Files (${component.files.length}):');
    for (final file in component.files) {
      stdout.writeln('  $file');
    }
    if (component.userOwned.isNotEmpty) {
      stdout.writeln('User-owned (never overwritten):');
      for (final file in component.userOwned) {
        stdout.writeln('  $file');
      }
    }
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}

String _importPath(String installRoot, String entry) =>
    "package:<your_app>/${_join(installRoot, entry)}";

String _join(String root, String entry) {
  final normalizedRoot =
      root.endsWith('/') ? root.substring(0, root.length - 1) : root;
  return '$normalizedRoot/$entry';
}

void _printList(String label, List<String> values) {
  stdout.writeln('$label: ${values.isEmpty ? '(none)' : values.join(', ')}');
}
