import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/discovery_commands.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/multi_registry_manager.dart';

Future<int> runSearchCommand({
  required ArgResults searchCommand,
  required MultiRegistryManager multiRegistry,
  required CliLogger logger,
}) async {
  if (searchCommand['help'] == true) {
    print('Usage: flutter_shadcn search <query> [--refresh] [--json]');
    print(
        '       flutter_shadcn search @<namespace> [query] [--refresh] [--json]');
    print('');
    print('Searches for components by name, description, or tags.');
    print('Options:');
    print('  --refresh  Refresh cache from remote');
    print('  --json     Output machine-readable JSON');
    return ExitCodes.success;
  }

  String? searchNamespaceOverride;
  final searchTokens = [...searchCommand.rest];
  if (searchTokens.isNotEmpty &&
      searchTokens.first.startsWith('@') &&
      !searchTokens.first.contains('/')) {
    searchNamespaceOverride = searchTokens.removeAt(0).substring(1).trim();
    if (searchNamespaceOverride.isEmpty) {
      stderr.writeln('Error: Invalid namespace token for search.');
      return ExitCodes.usage;
    }
  }

  final searchQuery = searchTokens.join(' ');
  final target = await multiRegistry.resolveDiscoveryTarget(
    namespace: searchNamespaceOverride,
  );

  if (searchQuery.isEmpty) {
    final listExit = await handleListCommand(
      registryBaseUrl: target.registryBase,
      registryId: target.registryId,
      refresh: searchCommand['refresh'] == true,
      offline: multiRegistry.offline,
      jsonOutput: searchCommand['json'] == true,
      logger: logger,
      indexPath: target.indexPath,
      indexSchemaPath: target.indexSchemaPath,
    );
    return listExit;
  }

  final searchExit = await handleSearchCommand(
    query: searchQuery,
    registryBaseUrl: target.registryBase,
    registryId: target.registryId,
    refresh: searchCommand['refresh'] == true,
    offline: multiRegistry.offline,
    jsonOutput: searchCommand['json'] == true,
    logger: logger,
    indexPath: target.indexPath,
    indexSchemaPath: target.indexSchemaPath,
  );
  return searchExit;
}
