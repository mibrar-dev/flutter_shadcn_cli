import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/multi_registry_manager.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/arg_helpers.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';

Future<int> runAddCommand({
  required ArgResults addCommand,
  required MultiRegistryManager multiRegistry,
}) async {
  final Set<String> includeFileKinds;
  final Set<String> excludeFileKinds;
  try {
    includeFileKinds = parseFileKindOptions(
      addCommand['include-files'] as List,
      optionName: 'include-files',
    );
    excludeFileKinds = parseFileKindOptions(
      addCommand['exclude-files'] as List,
      optionName: 'exclude-files',
    );
  } on CliArgumentException catch (e) {
    stderr.writeln(e.message);
    return ExitCodes.usage;
  }
  if (includeFileKinds.isNotEmpty && excludeFileKinds.isNotEmpty) {
    stderr.writeln(
      'Error: --include-files and --exclude-files cannot be used together.',
    );
    return ExitCodes.usage;
  }

  if (addCommand['help'] == true) {
    print(
        'Usage: flutter_shadcn add <@namespace/component> [<@namespace/component> ...]');
    print(
        '       flutter_shadcn add <component> [<component> ...]  # resolves using default/enabled registries');
    print('Options:');
    print(
        '  --include-files   Optional kinds to include: readme, preview, meta');
    print(
        '  --exclude-files   Optional kinds to exclude: readme, preview, meta');
    print('  --help, -h         Show this message');
    return ExitCodes.success;
  }
  final rest = addCommand.rest;
  if (rest.isEmpty) {
    print('Usage: flutter_shadcn add <component>');
    print('       flutter_shadcn add @namespace/component');
    return ExitCodes.usage;
  }

  try {
    await multiRegistry.runAdd(
      rest,
      includeFileKinds: includeFileKinds,
      excludeFileKinds: excludeFileKinds,
    );
    return ExitCodes.success;
  } catch (e) {
    stderr.writeln('Error: $e');
    if (e is RegistrySchemaValidationException ||
        '$e'.contains('schema validation failed')) {
      return ExitCodes.schemaInvalid;
    }
    if ('$e'.contains('ambiguous')) {
      return ExitCodes.usage;
    }
    return ExitCodes.componentMissing;
  }
}
