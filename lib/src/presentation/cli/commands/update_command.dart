import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_source.dart';
import 'package:flutter_shadcn_cli/src/application/services/update/update_service.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_context.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_support.dart';

/// `flutter_shadcn update [ids…] [--all] [--check] [--json]`
/// (P5_CLI_PLAN.md §2.3, new in v2).
///
/// Hash-driven: overwrite files whose disk bytes still match the lock, report
/// locally modified files and leave them, and never read or write user-owned
/// `<name>_theme.dart` files.
Future<int> runUpdateCommand({
  required ArgResults updateCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(updateCommand, 'json');
  final check = commandFlag(updateCommand, 'check');
  final logger = commandLogger(rootArgs, json: json);

  if (commandFlag(updateCommand, 'help')) {
    _printUpdateHelp();
    return ExitCodes.success;
  }

  final includeAll = commandFlag(updateCommand, 'all');
  final ids = componentIdsFrom(updateCommand);
  if (!includeAll && ids.isNotEmpty == false) {
    // No ids and no --all: update every installed component.
  }

  try {
    final context = await CommandContextResolver.resolve(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    Set<String>? componentFilter;
    if (!includeAll && ids.isNotEmpty) {
      componentFilter = ids.toSet();
    } else if (!includeAll && ids.isEmpty) {
      final lock = await ShadcnLockRepository(projectRoot).load();
      componentFilter = lock.componentIds.toSet();
    }

    final service = UpdateService(
      manifest: context.loadedManifest.manifest,
      reader: RegistrySourceFileReader(context.source),
      projectRoot: projectRoot,
      installRoot: context.installRoot,
      manifestSha256: context.loadedManifest.sha256,
      themeRegenerator: (presetId) =>
          context.themeService.apply(presetId, refresh: true),
    );
    final report =
        await service.run(componentIds: componentFilter, check: check);

    if (json) {
      final exitCode = check && report.needsAttention ? 1 : ExitCodes.success;
      printJson(jsonEnvelope(
        command: 'update',
        data: report.toJson(),
        meta: {'exitCode': exitCode},
      ));
      return exitCode;
    }
    report.writeHuman(logger);
    if (check && report.needsAttention) {
      return 1;
    }
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}

void _printUpdateHelp() {
  stdout.writeln('Usage: flutter_shadcn update [component...] [flags]');
  stdout.writeln('       flutter_shadcn update --all [flags]');
  stdout.writeln('');
  stdout.writeln(
      'Updates installed components to the registry\'s current files.');
  stdout
      .writeln('Files you edited are reported and left untouched; user-owned');
  stdout.writeln('<name>_theme.dart files are never rewritten.');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --all     Update every installed component');
  stdout.writeln(
      '  --check   Report only; exit 1 when anything is behind or modified');
  stdout.writeln('  --json    Machine-readable output on stdout');
}
