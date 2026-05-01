import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/discovery_commands.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/registry_selection.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/runtime_roots.dart';

Future<int> runListCommand({
  required ArgResults listCommand,
  required ArgResults rootArgs,
  required String? localRegistryRoot,
  required String? cliRoot,
  required ShadcnConfig config,
  required bool offline,
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

  final roots =
      ResolvedRoots(localRegistryRoot: localRegistryRoot, cliRoot: cliRoot);
  final selection = resolveRegistrySelection(
    rootArgs,
    roots,
    config,
    offline,
    namespaceOverride: listNamespaceOverride,
  );
  final registryUrl = selection.registryRoot.root;
  final listExit = await handleListCommand(
    registryBaseUrl: registryUrl,
    registryId: sanitizeCacheKey(registryUrl),
    refresh: listCommand['refresh'] == true,
    offline: offline,
    jsonOutput: listCommand['json'] == true,
    logger: logger,
    indexPath: selection.indexPath,
    indexSchemaPath: selection.indexSchemaPath,
  );
  return listExit;
}
