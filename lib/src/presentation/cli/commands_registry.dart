import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/dto/registry_summary.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_source_resolver.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry_directory/registry_directory_client.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry_directory/registry_directory_entry.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_support.dart';

/// `flutter_shadcn registries [--json]`: configured + discoverable registries
/// (P5_CLI_PLAN.md §2).
Future<int> runRegistriesCommand({
  required ArgResults command,
  required ArgResults rootArgs,
  required String projectRoot,
}) async {
  final json = commandFlag(command, 'json');
  if (commandFlag(command, 'help')) {
    stdout.writeln('Usage: flutter_shadcn registries [--json]');
    stdout.writeln('');
    stdout.writeln('Lists configured and discoverable registries.');
    return ExitCodes.success;
  }
  final config = await ShadcnConfig.load(projectRoot);
  final summaries = await _collectSummaries(config, projectRoot);

  if (json) {
    printJson(jsonEnvelope(
      command: 'registries',
      data: {
        'defaultNamespace': config.effectiveDefaultNamespace,
        'items': summaries.map((summary) => summary.toJson()).toList(),
      },
      meta: {'exitCode': ExitCodes.success},
    ));
    return ExitCodes.success;
  }
  if (summaries.isEmpty) {
    stdout.writeln('No registries configured.');
    return ExitCodes.success;
  }
  stdout.writeln('Registries:');
  for (final summary in summaries) {
    final marker = summary.isDefault ? ' (default)' : '';
    stdout.writeln('  ${summary.namespace}$marker');
    stdout.writeln('    source: ${summary.source}');
    if (summary.mode != null) {
      stdout.writeln('    mode: ${summary.mode}');
    }
    if (summary.baseUrl?.isNotEmpty == true) {
      stdout.writeln('    baseUrl: ${summary.baseUrl}');
    }
    if (summary.registryPath?.isNotEmpty == true) {
      stdout.writeln('    path: ${summary.registryPath}');
    }
  }
  return ExitCodes.success;
}

/// `flutter_shadcn default [namespace] [--local | --remote]`
/// (P5_CLI_PLAN.md §2).
Future<({ShadcnConfig config, int exitCode})> runDefaultCommand({
  required ArgResults command,
  required ArgResults rootArgs,
  required ShadcnConfig config,
  required String projectRoot,
}) async {
  final logger = commandLogger(rootArgs, json: false);
  if (commandFlag(command, 'help')) {
    stdout.writeln(
        'Usage: flutter_shadcn default [namespace] [--local|--remote]');
    stdout.writeln('');
    stdout.writeln('Sets the default registry namespace and source mode.');
    return (config: config, exitCode: ExitCodes.success);
  }
  final wantsLocal = commandFlag(command, 'local');
  final wantsRemote = commandFlag(command, 'remote');
  if (wantsLocal && wantsRemote) {
    logger
        .errorToStderr('Error: --local and --remote cannot be used together.');
    return (config: config, exitCode: ExitCodes.usage);
  }
  final namespace = command.rest.isNotEmpty
      ? command.rest.first.trim()
      : config.effectiveDefaultNamespace;

  if (!wantsLocal && !wantsRemote && command.rest.isEmpty) {
    stdout.writeln(
        'Current default registry: ${config.effectiveDefaultNamespace}');
    if (config.registryMode != null) {
      stdout.writeln('Mode: ${config.registryMode}');
    }
    if (config.registryPath?.isNotEmpty == true) {
      stdout.writeln('Registry path: ${config.registryPath}');
    }
    if (config.registryUrl?.isNotEmpty == true) {
      stdout.writeln('Registry URL: ${config.registryUrl}');
    }
    return (config: config, exitCode: ExitCodes.success);
  }

  var next = config.copyWith(defaultNamespace: namespace);
  if (wantsRemote) {
    next = next.copyWith(
      registryMode: 'remote',
      registryPath: null,
      registryUrl: RegistrySourceResolver.defaultBaseUrl(),
    );
  } else if (wantsLocal) {
    stdout.write('Path to local registry root: ');
    final registryPath = stdin.readLineSync()?.trim() ?? '';
    if (registryPath.isEmpty) {
      logger.errorToStderr('Error: registry path is required for local mode.');
      return (config: config, exitCode: ExitCodes.usage);
    }
    next = next.copyWith(
      registryMode: 'local',
      registryPath: registryPath,
      registryUrl: null,
    );
  }
  await ShadcnConfig.save(projectRoot, next);
  stdout.writeln(
    'Default registry set to: ${next.effectiveDefaultNamespace}'
    '${wantsRemote ? ' (remote)' : wantsLocal ? ' (local)' : ''}',
  );
  return (config: next, exitCode: ExitCodes.success);
}

Future<List<RegistrySummary>> _collectSummaries(
  ShadcnConfig config,
  String projectRoot,
) async {
  final summaries = <String, RegistrySummary>{};
  final defaultNamespace = config.effectiveDefaultNamespace;
  config.registries?.forEach((namespace, entry) {
    summaries[namespace] = RegistrySummary(
      namespace: namespace,
      displayName: namespace,
      isDefault: namespace == defaultNamespace,
      enabled: entry.enabled,
      source: 'config',
      mode: entry.registryMode,
      baseUrl: entry.baseUrl ?? entry.registryUrl,
      registryPath: entry.registryPath,
      installRoot: entry.installPath,
      capabilitySharedGroups: entry.capabilitySharedGroups,
      capabilityComposites: entry.capabilityComposites,
      capabilityTheme: entry.capabilityTheme,
    );
  });

  final client = RegistryDirectoryClient();
  try {
    final directory = await client.load(
      projectRoot: projectRoot,
      directoryPath: config.registriesPath,
      offline: false,
    );
    for (final entry in directory.registries) {
      final existing = summaries[entry.namespace];
      summaries[entry.namespace] =
          _mergeDirectory(entry, existing, defaultNamespace);
    }
  } catch (_) {
    // The directory is optional; the configured entries above still list.
  } finally {
    client.close();
  }

  return summaries.values.toList()
    ..sort((a, b) => a.namespace.compareTo(b.namespace));
}

RegistrySummary _mergeDirectory(
  RegistryDirectoryEntry entry,
  RegistrySummary? existing,
  String defaultNamespace,
) {
  return RegistrySummary(
    namespace: entry.namespace,
    displayName: entry.displayName,
    isDefault: entry.namespace == defaultNamespace,
    enabled: existing?.enabled ?? true,
    source: existing == null ? 'directory' : 'config+directory',
    mode: existing?.mode ?? 'remote',
    baseUrl: existing?.baseUrl ?? entry.baseUrl,
    registryPath: existing?.registryPath,
    installRoot: existing?.installRoot ?? entry.installRoot,
    capabilitySharedGroups:
        existing?.capabilitySharedGroups ?? entry.capabilities.sharedGroups,
    capabilityComposites:
        existing?.capabilityComposites ?? entry.capabilities.composites,
    capabilityTheme: existing?.capabilityTheme ?? entry.capabilities.theme,
  );
}
