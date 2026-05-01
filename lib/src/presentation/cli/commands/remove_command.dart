import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer_orchestrator.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/core/utils/component_ref_normalizer.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/installer.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/multi_registry_manager.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/arg_helpers.dart';

Future<int> runRemoveCommand({
  required ArgResults removeCommand,
  required Installer? installer,
  required MultiRegistryManager multiRegistry,
  required ArgResults rootArgs,
  required ShadcnConfig config,
  required String? preloadedNamespace,
  required CliLogger logger,
}) async {
  if (removeCommand['help'] == true) {
    print('Usage: flutter_shadcn remove <component> [<component> ...]');
    print('       flutter_shadcn remove --all');
    print('Options:');
    print('  --all, -a          Remove every installed component');
    print('  --force, -f        Force removal even if dependencies remain');
    print('  --help, -h         Show this message');
    return ExitCodes.success;
  }
  final rest = removeCommand.rest;
  final removeAll = removeCommand['all'] == true || rest.contains('all');
  if (removeAll) {
    final activeInstaller = installer;
    if (activeInstaller == null) {
      stderr.writeln('Error: Installer is not available.');
      return ExitCodes.registryNotFound;
    }
    final orchestrator = InstallerOrchestrator(activeInstaller);
    final namespace =
        preloadedNamespace ?? selectedNamespaceForCommand(rootArgs, config);
    await multiRegistry.rollbackInlineAssets(
      namespace: namespace,
      removeIcons: true,
      removeTypography: true,
      removeAll: true,
    );
    await orchestrator.removeAllComponents();
    return ExitCodes.success;
  }
  if (rest.isEmpty) {
    print('Usage: flutter_shadcn remove <component>');
    return ExitCodes.usage;
  }

  final force = removeCommand['force'] == true;
  final selectedNamespace =
      preloadedNamespace ?? selectedNamespaceForCommand(rootArgs, config);
  var currentNamespace = selectedNamespace;
  final normalized = <String>[];
  var inlineRollbackApplied = false;
  for (final token in rest) {
    final parsed = MultiRegistryManager.parseComponentRef(token);
    if (parsed == null && ComponentRefNormalizer.looksQualified(token)) {
      stderr.writeln(
        'Error: Invalid component address "$token". Use @namespace/component',
      );
      return ExitCodes.usage;
    }
    final componentName = parsed?.componentId ?? token;
    final namespace = parsed?.namespace ?? currentNamespace;
    if (parsed != null &&
        namespace != selectedNamespace &&
        !isDefaultNamespaceAliasAllowed(parsed.namespace, config)) {
      stderr.writeln(
        'Error: remove with @namespace/component requires --registry-name for that namespace.',
      );
      return ExitCodes.configInvalid;
    }
    if (componentName == 'icon_fonts' || componentName == 'typography_fonts') {
      final rolledBack = await multiRegistry.rollbackInlineAssets(
        namespace: namespace,
        removeIcons: componentName == 'icon_fonts',
        removeTypography: componentName == 'typography_fonts',
        removeAll: false,
      );
      if (rolledBack) {
        inlineRollbackApplied = true;
        continue;
      }
    }
    normalized.add(componentName);
  }

  if (normalized.isEmpty && inlineRollbackApplied) {
    logger.success('Removed inline-managed asset actions.');
    return ExitCodes.success;
  }

  final activeInstaller = installer;
  if (activeInstaller == null) {
    stderr.writeln('Error: Installer is not available.');
    return ExitCodes.registryNotFound;
  }
  final orchestrator = InstallerOrchestrator(activeInstaller);
  await orchestrator.removeComponents(normalized, force: force);
  await orchestrator.regenerateAliases();
  return ExitCodes.success;
}
