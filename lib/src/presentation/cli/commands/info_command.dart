import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/services/manifest_closure.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_context.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_support.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_block.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_component.dart';

/// `flutter_shadcn info <component|block> [--json]`: dependency closure, files
/// and api of one component, or the files, viewport and closure of one block
/// (P5_CLI_PLAN.md §2, P6-B2).
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
    stdout.writeln('Usage: flutter_shadcn info <component|block> [--json]');
    stdout.writeln('');
    stdout.writeln('Shows the closure, files and api of a component, or the '
        'files and closure of a block.');
    return ExitCodes.success;
  }

  final ids = componentIdsFrom(infoCommand);
  if (ids.isEmpty) {
    stdout.writeln('Usage: flutter_shadcn info <component|block>');
    return ExitCodes.usage;
  }
  if (ids.length > 1) {
    logger.errorToStderr(
      'Error: info accepts a single id. Got ${ids.length}: '
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
    if (component != null) {
      return await _writeComponent(context, component, json: json);
    }
    final block = manifest.blocks[id];
    if (block != null) {
      return await _writeBlock(context, block, json: json);
    }
    if (json) {
      printJson(jsonEnvelope(
        command: 'info',
        data: {'id': id},
        errors: [
          jsonError(
            code: ExitCodeLabels.componentMissing,
            message: '"$id" is not a component or a block in the registry '
                'manifest.',
          ),
        ],
        meta: {'exitCode': ExitCodes.componentMissing},
      ));
    } else {
      logger.errorToStderr(
          'Error: "$id" is not a component or a block in the registry.');
    }
    return ExitCodes.componentMissing;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}

Future<int> _writeComponent(
  CommandContext context,
  ManifestComponent component, {
  required bool json,
}) async {
  final manifest = context.loadedManifest.manifest;
  final closure = ManifestClosureResolver(manifest).resolve([component.id]);
  final data = <String, dynamic>{
    'id': component.id,
    'kind': 'component',
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

  stdout.writeln('${component.id} — ${component.name} (component)');
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
}

Future<int> _writeBlock(
  CommandContext context,
  ManifestBlock block, {
  required bool json,
}) async {
  final manifest = context.loadedManifest.manifest;
  final closure = ManifestClosureResolver(manifest).resolve(
    const [],
    blockIds: [block.id],
  );
  final data = <String, dynamic>{
    'id': block.id,
    'kind': 'block',
    'name': block.name,
    'category': block.category,
    'description': block.description,
    'tags': block.tags,
    'viewport': block.viewport,
    'entry': block.entry,
    'installRoot': context.installRoot,
    'install': block.install ?? 'flutter_shadcn add ${block.id}',
    'import': _importPath(context.installRoot, block.entry),
    'files': block.files,
    'docs': block.docs,
    'deps': {
      'components': block.deps.components,
      'primitives': block.deps.primitives,
      'foundation': block.deps.foundation,
      'theme': block.deps.theme,
    },
    'closure': {
      'blocks': closure.blocks,
      'components': closure.components,
      'primitives': closure.primitives,
    },
  };

  if (json) {
    printJson(jsonEnvelope(
      command: 'info',
      data: data,
      meta: {'exitCode': ExitCodes.success},
    ));
    return ExitCodes.success;
  }

  stdout.writeln('${block.id} — ${block.name} (block)');
  stdout.writeln('  category:    ${block.category}');
  stdout.writeln('  viewport:    ${block.viewport}');
  stdout.writeln('  description: ${block.description}');
  if (block.tags.isNotEmpty) {
    stdout.writeln('  tags:        ${block.tags.join(', ')}');
  }
  stdout.writeln('  install:     ${data['install']}');
  stdout.writeln('  import:      ${data['import']}');
  stdout.writeln('');
  stdout.writeln('Dependencies (direct):');
  _printList('  components', block.deps.components);
  _printList('  primitives', block.deps.primitives);
  _printList('  foundation', block.deps.foundation);
  _printList('  theme', block.deps.theme);
  stdout.writeln('');
  stdout.writeln('Closure:');
  _printList('  components', closure.components);
  _printList('  primitives', closure.primitives);
  stdout.writeln('');
  stdout.writeln('Files (${block.files.length}):');
  for (final file in block.files) {
    stdout.writeln('  $file');
  }
  if (block.docs.isNotEmpty) {
    stdout.writeln('Docs (not copied into the app):');
    for (final doc in block.docs) {
      stdout.writeln('  $doc');
    }
  }
  return ExitCodes.success;
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
