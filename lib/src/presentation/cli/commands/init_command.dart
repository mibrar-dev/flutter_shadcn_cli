import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/multi_registry_manager.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';

Future<int> runInitCommand({
  required ArgResults initCommand,
  required MultiRegistryManager multiRegistry,
  required String defaultNamespace,
}) async {
  if (initCommand['help'] == true) {
    print('Usage: flutter_shadcn init [@namespace|namespace]');
    print('');
    print('Runs inline bootstrap actions for the selected namespace.');
    print('Defaults to current default namespace (shadcn by default).');
    print('Options:');
    print('  --yes, -y          Non-interactive init (apply defaults)');
    return ExitCodes.success;
  }
  if (initCommand.rest.length > 1) {
    stderr.writeln('Error: init accepts at most one namespace.');
    stderr.writeln('Usage: flutter_shadcn init [@namespace|namespace]');
    return ExitCodes.usage;
  }
  final namespace = initCommand.rest.isNotEmpty
      ? _parseInitNamespaceToken(initCommand.rest.first)
      : defaultNamespace;
  final assumeYes = initCommand['yes'] == true;
  try {
    await multiRegistry.runNamespaceInit(namespace, assumeYes: assumeYes);
    return ExitCodes.success;
  } catch (e) {
    stderr.writeln('Error: $e');
    if (e is RegistrySchemaValidationException ||
        '$e'.contains('schema validation failed')) {
      return ExitCodes.schemaInvalid;
    }
    return ExitCodes.configInvalid;
  }
}

String _parseInitNamespaceToken(String token) {
  final trimmed = token.trim();
  if (trimmed.startsWith('@') && trimmed.length > 1) {
    return trimmed.substring(1);
  }
  return trimmed;
}
