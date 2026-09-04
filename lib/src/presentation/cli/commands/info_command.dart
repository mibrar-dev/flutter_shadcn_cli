import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/core/utils/component_ref_normalizer.dart';
import 'package:flutter_shadcn_cli/src/discovery_commands.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/installer.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/multi_registry_manager.dart';
import 'package:flutter_shadcn_cli/src/registry/component.dart';

Future<int> runInfoCommand({
  required ArgResults infoCommand,
  required MultiRegistryManager multiRegistry,
  required CliLogger logger,
  Installer? installer,
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
  if (infoCommand.rest.length > 1) {
    return _rejectMultipleComponents(
      infoCommand: infoCommand,
      ids: infoCommand.rest,
    );
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

  late final DiscoveryRegistryTarget target;
  try {
    target = await multiRegistry.resolveDiscoveryTarget(
      namespace: namespaceOverride,
    );
  } on MultiRegistryException catch (e) {
    // Mirror list_command: clean registry_not_found envelope, never crash,
    // never prompt (especially in --json mode).
    if (infoCommand['json'] == true) {
      printJson(jsonEnvelope(
        command: 'info',
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
  final registryComponent = _resolveManifestComponent(
    installer: installer,
    componentId: componentId,
    discoveryNamespace: target.namespace,
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
    registryComponent: registryComponent,
  );
  return infoExit;
}

/// Fails loudly when more than one component is requested: `info` only
/// supports a single component, so silently answering the first one would
/// mislead scripts and users.
int _rejectMultipleComponents({
  required ArgResults infoCommand,
  required List<String> ids,
}) {
  const message =
      'info accepts a single component id. Pass one component per invocation.';
  if (infoCommand['json'] == true) {
    printJson(jsonEnvelope(
      command: 'info',
      data: {
        'ids': ids,
      },
      errors: [
        jsonError(
          code: ExitCodeLabels.usage,
          message: '$message Got ${ids.length}: ${ids.join(', ')}.',
          details: {'ids': ids, 'supported': 1},
        ),
      ],
      meta: {'exitCode': ExitCodes.usage},
    ));
    return ExitCodes.usage;
  }
  stderr.writeln('Error: $message Got ${ids.length}: ${ids.join(', ')}.');
  return ExitCodes.usage;
}

/// Looks up the manifest-backed registry component so `info` can advertise
/// an import path that is actually installed. Returns `null` when no
/// preloaded installer is available or when it belongs to a different
/// registry namespace than the one being described.
Component? _resolveManifestComponent({
  required Installer? installer,
  required String componentId,
  required String discoveryNamespace,
}) {
  final activeInstaller = installer;
  if (activeInstaller == null) {
    return null;
  }
  final installerNamespace = activeInstaller.registryNamespace;
  if (installerNamespace != null && installerNamespace != discoveryNamespace) {
    return null;
  }
  try {
    return activeInstaller.registry.getComponent(componentId);
  } catch (_) {
    return null;
  }
}
