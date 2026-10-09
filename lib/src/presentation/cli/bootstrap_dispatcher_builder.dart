import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/application/services/reset/global_reset_service.dart';
import 'package:flutter_shadcn_cli/src/application/services/reset/project_reset_service.dart';
import 'package:flutter_shadcn_cli/src/application/services/reset/reset_snapshot_store.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/core/utils/path_utils.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_context.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_dispatcher.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_support.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/add_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/audit_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/dry_run_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/feedback_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/info_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/init_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/list_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/project_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/remove_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/reset_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/search_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/sync_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/theme_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/update_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/upgrade_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/validate_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/version_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands_doctor.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands_registry.dart';

/// Builds the v2 command dispatcher (P5_CLI_PLAN.md §2).
CommandDispatcher buildBootstrapCommandDispatcher({
  required ArgResults rootArgs,
  required ArgResults command,
  required String targetDir,
  required String? homeDirectory,
  required bool offline,
  required CliLogger logger,
  required ShadcnConfig Function() readConfig,
  required void Function(ShadcnConfig config) writeConfig,
}) {
  final registryOverride = registryOverrideFrom(rootArgs);

  Future<int> theme() async {
    final wantsHelp =
        command['help'] == true || command.command?['help'] == true;
    final context = wantsHelp
        ? null
        : await _resolveThemeInstaller(
            targetDir: targetDir,
            logger: logger,
            registryOverride: registryOverride,
            offline: offline,
          );
    return runThemeCommand(
      themeCommand: command,
      rootArgs: rootArgs,
      installer: context?.installer,
      registrySupportsTheme: null,
    );
  }

  return CommandDispatcher({
    'init': () => runInitCommand(
          initCommand: command,
          rootArgs: rootArgs,
          projectRoot: targetDir,
          registryOverride: registryOverride,
          offline: offline,
        ),
    'add': () => runAddCommand(
          addCommand: command,
          rootArgs: rootArgs,
          projectRoot: targetDir,
          registryOverride: registryOverride,
          offline: offline,
        ),
    'dry-run': () => runDryRunCommand(
          dryRunCommand: command,
          rootArgs: rootArgs,
          projectRoot: targetDir,
          registryOverride: registryOverride,
          offline: offline,
        ),
    'remove': () => runRemoveCommand(
          removeCommand: command,
          rootArgs: rootArgs,
          projectRoot: targetDir,
          registryOverride: registryOverride,
          offline: offline,
        ),
    'update': () => runUpdateCommand(
          updateCommand: command,
          rootArgs: rootArgs,
          projectRoot: targetDir,
          registryOverride: registryOverride,
          offline: offline,
        ),
    'list': () => runListCommand(
          listCommand: command,
          rootArgs: rootArgs,
          projectRoot: targetDir,
          registryOverride: registryOverride,
          offline: offline,
        ),
    'search': () => runSearchCommand(
          searchCommand: command,
          rootArgs: rootArgs,
          projectRoot: targetDir,
          registryOverride: registryOverride,
          offline: offline,
        ),
    'info': () => runInfoCommand(
          infoCommand: command,
          rootArgs: rootArgs,
          projectRoot: targetDir,
          registryOverride: registryOverride,
          offline: offline,
        ),
    'doctor': () => runDoctorCommand(
          doctorCommand: command,
          rootArgs: rootArgs,
          projectRoot: targetDir,
          registryOverride: registryOverride,
          offline: offline,
        ),
    'validate': () => runValidateCommandCli(
          command: command,
          rootArgs: rootArgs,
          projectRoot: targetDir,
          registryOverride: registryOverride,
          offline: offline,
        ),
    'audit': () => runAuditCommandCli(
          command: command,
          rootArgs: rootArgs,
          projectRoot: targetDir,
          registryOverride: registryOverride,
          offline: offline,
        ),
    'sync': () => runSyncCommand(
          command: command,
          rootArgs: rootArgs,
          projectRoot: targetDir,
          registryOverride: registryOverride,
          offline: offline,
        ),
    'theme': theme,
    'registries': () => runRegistriesCommand(
          command: command,
          rootArgs: rootArgs,
          projectRoot: targetDir,
        ),
    'default': () async {
      final result = await runDefaultCommand(
        command: command,
        rootArgs: rootArgs,
        config: readConfig(),
        projectRoot: targetDir,
      );
      writeConfig(result.config);
      return result.exitCode;
    },
    'reset': () => runResetCommand(
          command: command,
          service: GlobalResetService(
            homeDirectory: homeDirectory ?? Directory.systemTemp.path,
          ),
        ),
    'project': () => _runProjectCommand(
          command: command,
          targetDir: targetDir,
          homeDirectory: homeDirectory,
          logger: logger,
          registryOverride: registryOverride,
          offline: offline,
        ),
    'version': () => runVersionCommand(command: command, logger: logger),
    'upgrade': () => runUpgradeCommand(command: command, logger: logger),
    'feedback': () => runFeedbackCommand(
          command: command,
          rootArgs: rootArgs,
          logger: logger,
          resolveRegistry: (_) => const FeedbackRegistryContext(
            namespace: 'shadcn_flutter',
            baseUrl: '',
          ),
        ),
  });
}

/// Resolves the installer for B6's theme command; `null` when the project has
/// no registry configured yet (the theme command reports that itself).
Future<CommandContext?> _resolveThemeInstaller({
  required String targetDir,
  required CliLogger logger,
  required String? registryOverride,
  required bool offline,
}) async {
  try {
    return await CommandContextResolver.resolve(
      projectRoot: targetDir,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
  } catch (_) {
    return null;
  }
}

Future<int> _runProjectCommand({
  required ArgResults command,
  required String targetDir,
  required String? homeDirectory,
  required CliLogger logger,
  required String? registryOverride,
  required bool offline,
}) async {
  final restHelp =
      command.rest.contains('--help') || command.rest.contains('-h');
  if (command['help'] == true || restHelp || command.command == null) {
    return runProjectCommand(
      command: command,
      resetProject: () => throw StateError('help requested'),
      undoProject: () => throw StateError('help requested'),
      refreshProject: () => throw StateError('help requested'),
    );
  }

  final projectRoot = findProjectRootFrom(targetDir);
  final snapshotStore = ResetSnapshotStore(
    homeDirectory: homeDirectory ?? Directory.systemTemp.path,
  );
  final resetService = ProjectResetService(
    projectRoot: projectRoot,
    snapshotStore: snapshotStore,
  );

  return runProjectCommand(
    command: command,
    resetProject: resetService.reset,
    undoProject: resetService.undo,
    refreshProject: () => _refreshProject(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    ),
  );
}

/// `project refresh`: re-apply the installed closure and the locked theme.
Future<ProjectRefreshOutput> _refreshProject({
  required String projectRoot,
  required CliLogger logger,
  required String? registryOverride,
  required bool offline,
}) async {
  final context = await CommandContextResolver.resolve(
    projectRoot: projectRoot,
    logger: logger,
    registryOverride: registryOverride,
    offline: offline,
  );
  final lock = await ShadcnLockRepository(projectRoot).load();
  final report =
      await context.installer.add(lock.componentIds, includeCore: true);
  final themeId = lock.theme?.id;
  if (themeId != null && themeId.isNotEmpty) {
    await context.themeService.apply(themeId, refresh: true);
  }
  return ProjectRefreshOutput(
    regeneratedFiles: report.written.length,
    repairedPaths: report.written,
  );
}
