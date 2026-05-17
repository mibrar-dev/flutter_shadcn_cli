import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/services/reset/global_reset_service.dart';
import 'package:flutter_shadcn_cli/src/application/services/reset/project_refresh_service.dart';
import 'package:flutter_shadcn_cli/src/application/services/reset/project_reset_service.dart';
import 'package:flutter_shadcn_cli/src/application/services/reset/reset_snapshot_store.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/core/utils/path_utils.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/installer.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/multi_registry_manager.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/arg_helpers.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_dispatcher.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/add_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/assets_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/audit_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/deps_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/dry_run_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/feedback_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/info_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/init_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/locale_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/list_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/project_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/remove_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/reset_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/search_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/sync_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/theme_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/upgrade_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/validate_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/version_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands_registry.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/registry_selection.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/runtime_roots.dart';

CommandDispatcher buildBootstrapCommandDispatcher({
  required ArgResults rootArgs,
  required ArgResults command,
  required ResolvedRoots roots,
  required String targetDir,
  required String? homeDirectory,
  required bool offline,
  required CliLogger logger,
  required MultiRegistryManager multiRegistry,
  required Installer? installer,
  required RegistrySelection? preloadedSelection,
  required ShadcnConfig Function() readConfig,
  required void Function(ShadcnConfig config) writeConfig,
}) {
  return CommandDispatcher({
    'registries': () => runRegistriesCommand(
          command: command,
          config: readConfig(),
          multiRegistry: multiRegistry,
        ),
    'default': () async {
      final result = await runDefaultCommand(
        command: command,
        config: readConfig(),
        multiRegistry: multiRegistry,
      );
      writeConfig(result.config);
      return result.exitCode;
    },
    'init': () => runInitCommand(
          initCommand: command,
          multiRegistry: multiRegistry,
          defaultNamespace: readConfig().effectiveDefaultNamespace,
        ),
    'locale': () => runLocaleCommand(command: command, targetDir: targetDir),
    'theme': () => runThemeCommand(
          themeCommand: command,
          rootArgs: rootArgs,
          installer: installer,
          registrySupportsTheme: preloadedSelection?.capabilityTheme,
        ),
    'add': () =>
        runAddCommand(addCommand: command, multiRegistry: multiRegistry),
    'dry-run': () =>
        runDryRunCommand(dryRunCommand: command, installer: installer),
    'remove': () => runRemoveCommand(
          removeCommand: command,
          installer: installer,
          multiRegistry: multiRegistry,
          rootArgs: rootArgs,
          config: readConfig(),
          preloadedNamespace: preloadedSelection?.namespace,
          logger: logger,
        ),
    'reset': () => runResetCommand(
          command: command,
          service: GlobalResetService(
            homeDirectory: homeDirectory ?? Directory.systemTemp.path,
          ),
        ),
    'project': () async {
      if (command['help'] == true ||
          command.command == null ||
          command.command?['help'] == true) {
        return runProjectCommand(
          command: command,
          resetProject: () => throw StateError('help requested'),
          undoProject: () => throw StateError('help requested'),
          refreshProject: () => throw StateError('help requested'),
        );
      }
      final config = readConfig();
      final projectRoot = findProjectRootFrom(targetDir);
      final snapshotStore = ResetSnapshotStore(
        homeDirectory: homeDirectory ?? Directory.systemTemp.path,
      );
      final projectResetService = ProjectResetService(
        projectRoot: projectRoot,
        snapshotStore: snapshotStore,
      );
      final namespace = selectedNamespaceForCommand(rootArgs, config);
      final registryEntry = await multiRegistry.findRegistryEntry(namespace);
      if (registryEntry == null) {
        stderr.writeln(
          'Error: Registry namespace "$namespace" was not found for project refresh.',
        );
        return ExitCodes.registryNotFound;
      }
      final projectRefreshService = ProjectRefreshService(
        projectRoot: projectRoot,
        executeActions: ({
          required projectRoot,
          required baseUrl,
          required actions,
          optionalActionDecider,
          groupSelector,
        }) {
          return multiRegistry.initActionEngine.executeActions(
            projectRoot: projectRoot,
            baseUrl: baseUrl,
            actions: actions,
            logger: logger,
            optionalActionDecider: optionalActionDecider,
            groupSelector: groupSelector,
          );
        },
      );
      return runProjectCommand(
        command: command,
        resetProject: projectResetService.reset,
        undoProject: projectResetService.undo,
        refreshProject: () async {
          final result = await projectRefreshService.refresh(
            registry: registryEntry,
            namespace: namespace,
            optionalActionDecider: _shouldRunOptionalProjectRefreshAction,
            groupSelector: _selectProjectRefreshGroups,
          );
          return ProjectRefreshOutput(
            regeneratedFiles: result.executionResult.filesWritten,
            repairedPaths: result.executionResult.record.filesWritten,
          );
        },
      );
    },
    'validate': () => runValidateCommandCli(
          command: command,
          registry: installer?.registry,
          offline: offline,
          logger: logger,
        ),
    'audit': () => runAuditCommandCli(
          command: command,
          registry: installer?.registry,
          targetDir: targetDir,
          config: readConfig(),
          logger: logger,
        ),
    'deps': () => runDepsCommandCli(
          command: command,
          registry: installer?.registry,
          targetDir: targetDir,
          config: readConfig(),
          logger: logger,
        ),
    'assets': () => runAssetsCommand(
          command: command,
          installer: installer,
          multiRegistry: multiRegistry,
          rootArgs: rootArgs,
          config: readConfig(),
          logger: logger,
        ),
    'platform': () async {
      final platformResult = await runPlatformCommand(
        command: command,
        config: readConfig(),
        targetDir: targetDir,
      );
      writeConfig(platformResult.config);
      return platformResult.exitCode;
    },
    'sync': () => runSyncCommand(command: command, installer: installer),
    'list': () => runListCommand(
          listCommand: command,
          multiRegistry: multiRegistry,
          logger: logger,
        ),
    'search': () => runSearchCommand(
          searchCommand: command,
          multiRegistry: multiRegistry,
          logger: logger,
        ),
    'info': () => runInfoCommand(
          infoCommand: command,
          multiRegistry: multiRegistry,
          logger: logger,
        ),
    'version': () => runVersionCommand(command: command, logger: logger),
    'upgrade': () => runUpgradeCommand(command: command, logger: logger),
    'feedback': () => runFeedbackCommand(
          command: command,
          rootArgs: rootArgs,
          logger: logger,
          resolveRegistry: (namespaceOverride) {
            final selection = resolveRegistrySelection(
              rootArgs,
              roots,
              readConfig(),
              offline,
              namespaceOverride: namespaceOverride,
            );
            return FeedbackRegistryContext(
              namespace: selection.namespace,
              baseUrl: selection.registryRoot.root,
            );
          },
        ),
  });
}

Future<bool> _shouldRunOptionalProjectRefreshAction(
  Map<String, dynamic> action,
) async {
  final label = action['promptLabel']?.toString().trim();
  if (label == null || label.isEmpty) {
    return false;
  }
  final description = action['promptDescription']?.toString().trim();
  stdout.writeln(label);
  if (description != null && description.isNotEmpty) {
    stdout.writeln(description);
  }
  stdout.write('Install? [Y/n]: ');
  final input = stdin.readLineSync()?.trim().toLowerCase();
  if (input == null || input.isEmpty) {
    return true;
  }
  return input == 'y' || input == 'yes';
}

Future<List<Map<String, dynamic>>> _selectProjectRefreshGroups(
  Map<String, dynamic> action,
  List<Map<String, dynamic>> groups,
) async {
  if (groups.isEmpty) {
    return const [];
  }
  final label = action['promptLabel']?.toString().trim();
  final description = action['promptDescription']?.toString().trim();
  if (label != null && label.isNotEmpty) {
    stdout.writeln(label);
  }
  if (description != null && description.isNotEmpty) {
    stdout.writeln(description);
  }
  stdout.writeln(
    'Select groups (comma-separated numbers, Enter for defaults):',
  );
  for (var i = 0; i < groups.length; i++) {
    final group = groups[i];
    final suffix = group['default'] == false ? '' : ' [default]';
    stdout.writeln('  ${i + 1}) ${group['label']}$suffix');
    final groupDescription = group['description']?.toString().trim();
    if (groupDescription != null && groupDescription.isNotEmpty) {
      stdout.writeln('     $groupDescription');
    }
  }
  stdout.write('Groups: ');
  final input = stdin.readLineSync()?.trim() ?? '';
  if (input.isEmpty) {
    return groups.where((group) => group['default'] != false).toList();
  }
  final selected = <Map<String, dynamic>>[];
  for (final token in input.split(',')) {
    final index = int.tryParse(token.trim());
    if (index == null || index < 1 || index > groups.length) {
      continue;
    }
    selected.add(groups[index - 1]);
  }
  return selected;
}
