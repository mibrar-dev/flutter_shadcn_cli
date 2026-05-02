import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/core/utils/component_ref_normalizer.dart';
import 'package:flutter_shadcn_cli/src/discovery_commands.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/multi_registry_manager.dart';

Future<int> runInfoCommand({
  required ArgResults infoCommand,
  required MultiRegistryManager multiRegistry,
  required CliLogger logger,
}) async {
  if (infoCommand['help'] == true) {
    print(
        'Usage: flutter_shadcn info <component-id|@namespace/component> [--refresh] [--json]');
    print('');
    print('Shows detailed information about a component.');
    print('Options:');
    print('  --refresh  Refresh cache from remote');
    print('  --json     Output machine-readable JSON');
    return ExitCodes.success;
  }
  final componentToken =
      infoCommand.rest.isNotEmpty ? infoCommand.rest.first : '';
  if (componentToken.isEmpty) {
    print('Usage: flutter_shadcn info <component-id>');
    return ExitCodes.usage;
  }
  String componentId = componentToken;
  String? namespaceOverride;
  final qualified = MultiRegistryManager.parseComponentRef(componentToken);
  if (qualified != null) {
    namespaceOverride = qualified.namespace;
    componentId = qualified.componentId;
  } else if (ComponentRefNormalizer.looksQualified(componentToken)) {
    stderr.writeln(
      'Error: Invalid component address "$componentToken". Use @namespace/component',
    );
    return ExitCodes.usage;
  }

  final target = await multiRegistry.resolveDiscoveryTarget(
    namespace: namespaceOverride,
  );
  final infoExit = await handleInfoCommand(
    componentId: componentId,
    registryBaseUrl: target.registryBase,
    registryId: target.registryId,
    refresh: infoCommand['refresh'] == true,
    offline: multiRegistry.offline,
    jsonOutput: infoCommand['json'] == true,
    logger: logger,
    indexPath: target.indexPath,
    indexSchemaPath: target.indexSchemaPath,
  );
  return infoExit;
}
