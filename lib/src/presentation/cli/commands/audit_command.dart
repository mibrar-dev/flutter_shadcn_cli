import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/services/command_health/audit_command.dart'
    as audit_service;
import 'package:flutter_shadcn_cli/src/application/services/registry_manifest_loader.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_source_resolver.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_support.dart';

/// `flutter_shadcn audit [--json]`: installed-vs-lock drift
/// (P5_CLI_PLAN.md §2).
Future<int> runAuditCommandCli({
  required ArgResults command,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(command, 'json');
  final logger = commandLogger(rootArgs, json: json);
  if (commandFlag(command, 'help')) {
    stdout.writeln('Usage: flutter_shadcn audit [--json]');
    stdout.writeln('');
    stdout.writeln('Compares installed files against shadcn.lock.');
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
    String? manifestSha256;
    try {
      manifestSha256 = (await RegistryManifestLoader(source).load()).sha256;
    } catch (_) {
      // Audit still reports lock drift when the manifest cannot be read.
    }
    return await audit_service.runAuditCommand(
      projectRoot: projectRoot,
      manifestSha256: manifestSha256,
      jsonOutput: json,
      logger: logger,
    );
  } catch (error) {
    return reportCommandError(error, logger);
  }
}
