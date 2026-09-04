import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/installer.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/multi_registry_manager.dart';

Future<int> runDryRunCommand({
  required ArgResults dryRunCommand,
  required Installer? installer,
}) async {
  if (dryRunCommand['help'] == true) {
    print(
        'Usage: flutter_shadcn dry-run <component|@namespace/component> [<component|@namespace/component> ...] [--json]');
    print('       flutter_shadcn dry-run --all [--json]');
    print('');
    print(
        'Shows what would be installed (dependencies, shared modules, assets, fonts).');
    print('Options:');
    print('  --all, -a          Include every available component');
    print('  --json             Output machine-readable JSON');
    print('  --help, -h         Show this message');
    return ExitCodes.success;
  }
  final activeInstaller = installer;
  if (activeInstaller == null) {
    stderr.writeln('Error: Installer is not available.');
    return ExitCodes.registryNotFound;
  }
  final rest = dryRunCommand.rest;
  final dryRunAll = dryRunCommand['all'] == true || rest.contains('all');
  final componentIds = <String>[];
  if (dryRunAll) {
    componentIds.addAll(activeInstaller.registry.components.map((c) => c.id));
  } else {
    if (rest.isEmpty) {
      print('Usage: flutter_shadcn dry-run <component> [<component> ...]');
      print('       flutter_shadcn dry-run --all');
      return ExitCodes.usage;
    }
    componentIds.addAll(rest.map(normalizeDryRunComponentRef));
  }
  final plan = await activeInstaller.buildDryRunPlan(componentIds);
  final hasMissing = plan.missing.isNotEmpty;
  final dryRunExitCode =
      hasMissing ? ExitCodes.componentMissing : ExitCodes.success;
  if (dryRunCommand['json'] == true) {
    final warnings = <Map<String, dynamic>>[];
    if (hasMissing) {
      warnings.add(jsonWarning(
        code: ExitCodeLabels.componentMissing,
        message: 'One or more components were not found.',
        details: {'missing': plan.missing},
      ));
    }
    final payload = jsonEnvelope(
      command: 'dry-run',
      data: plan.toJson(),
      warnings: warnings,
      meta: {'exitCode': dryRunExitCode},
    );
    printJson(payload);
  } else {
    activeInstaller.printDryRunPlan(plan);
  }
  return dryRunExitCode;
}

/// Normalizes a dry-run component reference the same way `add` and `info`
/// accept it: a qualified `@namespace/component` ref resolves to its bare
/// component id, while bare ids and malformed refs pass through unchanged
/// (unknown ids are reported as missing downstream).
String normalizeDryRunComponentRef(String token) {
  final qualified = MultiRegistryManager.parseComponentRef(token);
  return qualified?.componentId ?? token;
}
