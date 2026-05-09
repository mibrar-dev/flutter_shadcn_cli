import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/discovery_commands.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/multi_registry_manager.dart';

Future<int> runListCommand({
  required ArgResults listCommand,
  required MultiRegistryManager multiRegistry,
  required CliLogger logger,
}) async {
  if (listCommand['help'] == true) {
    print('Usage: flutter_shadcn list [--refresh] [--json]');
    print('       flutter_shadcn list @<namespace> [--refresh] [--json]');
    print('');
    print('Lists all available components from the registry.');
    print('Options:');
    print('  --refresh  Refresh cache from remote');
    print('  --json     Output machine-readable JSON');
    return ExitCodes.success;
  }
  String? listNamespaceOverride;
  final listTokens = [...listCommand.rest];
  if (listTokens.isNotEmpty &&
      listTokens.first.startsWith('@') &&
      !listTokens.first.contains('/')) {
    listNamespaceOverride = listTokens.removeAt(0).substring(1).trim();
    if (listNamespaceOverride.isEmpty) {
      stderr.writeln('Error: Invalid namespace token for list.');
      return ExitCodes.usage;
    }
  }
  if (listTokens.isNotEmpty) {
    stderr.writeln('Error: list does not accept positional query text.');
    stderr.writeln('Use: flutter_shadcn search [@namespace] <query>');
    return ExitCodes.usage;
  }

  late final DiscoveryRegistryTarget target;
  try {
    target = await multiRegistry.resolveDiscoveryTarget(
      namespace: listNamespaceOverride,
    );
  } on MultiRegistryException catch (e) {
    if (listCommand['json'] == true) {
      printJson(jsonEnvelope(
        command: 'list',
        data: const {},
        errors: [
          jsonError(
            code: ExitCodeLabels.registryNotFound,
            message: e.message,
          ),
        ],
        meta: {'exitCode': ExitCodes.registryNotFound},
      ));
    } else {
      stderr.writeln('Error: ${e.message}');
    }
    return ExitCodes.registryNotFound;
  }
  final listExit = await handleListCommand(
    registryBaseUrl: target.registryBase,
    registryId: target.registryId,
    refresh: listCommand['refresh'] == true,
    offline: multiRegistry.offline,
    jsonOutput: listCommand['json'] == true,
    logger: logger,
    indexPath: target.indexPath,
    indexSchemaPath: target.indexSchemaPath,
  );
  return listExit;
}
