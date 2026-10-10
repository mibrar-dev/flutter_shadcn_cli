import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/services/command_health/validate_command.dart'
    as validate_service;
import 'package:flutter_shadcn_cli/src/application/services/registry_source_resolver.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_support.dart';

/// `flutter_shadcn validate [--json]`: validate the registry manifest against
/// the v2 schema (P5_CLI_PLAN.md §2).
Future<int> runValidateCommandCli({
  required ArgResults command,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(command, 'json');
  final logger = commandLogger(rootArgs, json: json);
  if (commandFlag(command, 'help')) {
    stdout.writeln('Usage: flutter_shadcn validate [--json]');
    stdout.writeln('');
    stdout.writeln('Validates manifests/registry.json against the v2 schema.');
    return ExitCodes.success;
  }
  try {
    final config = await ShadcnConfig.load(projectRoot);
    final source = RegistrySourceResolver.resolve(
      projectRoot: projectRoot,
      config: config,
      registryOverride: registryOverride,
      offline: offline,
    );
    return await validate_service.runValidateCommand(
      source: source,
      jsonOutput: json,
      logger: logger,
    );
  } catch (error) {
    return reportCommandError(error, logger);
  }
}
