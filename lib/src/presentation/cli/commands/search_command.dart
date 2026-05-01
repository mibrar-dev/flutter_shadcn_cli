import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/discovery_commands.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/registry_selection.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/runtime_roots.dart';

Future<int> runSearchCommand({
  required ArgResults searchCommand,
  required ArgResults rootArgs,
  required String? localRegistryRoot,
  required String? cliRoot,
  required ShadcnConfig config,
  required bool offline,
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
  final roots = ResolvedRoots(
    localRegistryRoot: localRegistryRoot,
    cliRoot: cliRoot,
  );
  final selection = resolveRegistrySelection(
    rootArgs,
    roots,
    config,
    offline,
    namespaceOverride: searchNamespaceOverride,
  );
  final registryUrl = selection.registryRoot.root;

  if (searchQuery.isEmpty) {
    final listExit = await handleListCommand(
      registryBaseUrl: registryUrl,
      registryId: sanitizeCacheKey(registryUrl),
      refresh: searchCommand['refresh'] == true,
      offline: offline,
      jsonOutput: searchCommand['json'] == true,
      logger: logger,
      indexPath: selection.indexPath,
      indexSchemaPath: selection.indexSchemaPath,
    );
    return listExit;
  }

  final searchExit = await handleSearchCommand(
    query: searchQuery,
    registryBaseUrl: registryUrl,
    registryId: sanitizeCacheKey(registryUrl),
    refresh: searchCommand['refresh'] == true,
    offline: offline,
    jsonOutput: searchCommand['json'] == true,
    logger: logger,
    indexPath: selection.indexPath,
    indexSchemaPath: selection.indexSchemaPath,
  );
  return searchExit;
}
