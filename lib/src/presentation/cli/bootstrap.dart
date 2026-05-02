import 'dart:io';
import 'dart:async';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_shadcn_cli/src/installer.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry_directory.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/multi_registry_manager.dart';
import 'package:flutter_shadcn_cli/src/version_manager.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_dispatcher.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/add_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/assets_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/audit_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/deps_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/dry_run_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/docs_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/feedback_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/info_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/init_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/install_skill_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/list_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/remove_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/search_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/sync_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands_registry.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/arg_helpers.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/theme_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/upgrade_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/validate_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/version_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands_doctor.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/registry_selection.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/runtime_roots.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/bootstrap_support.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/registry_bootstrap_exception.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/usage.dart';

Future<void> runCliBootstrap(List<String> arguments) async {
  _ensureExecutablePath();
  final parser = buildCliParser();

  final normalizedArgs = normalizeCliArgs(arguments);
  ArgResults argResults;
  try {
    argResults = parser.parse(normalizedArgs);
  } catch (e) {
    print('Error: $e');
    exit(ExitCodes.usage);
  }

  final advanced = argResults['advanced'] == true;
  if (argResults['help'] == true) {
    printCliUsage(advanced: advanced);
    exit(0);
  }

  if (argResults.command == null) {
    printCliUsage(advanced: advanced);
    exit(ExitCodes.usage);
  }

  final advancedGateError = _advancedGateError(argResults, advanced);
  if (advancedGateError != null) {
    stderr.writeln('Error: $advancedGateError');
    exit(ExitCodes.usage);
  }

  final targetDir = Directory.current.path;
  final roots = await resolveRoots();
  final verbose = argResults['verbose'] == true;
  final offline = argResults['offline'] == true;
  final logger = CliLogger(verbose: verbose);
  var config = await ShadcnConfig.load(targetDir);
  final registriesPath =
      optionalStringOption(argResults, 'registries-path')?.trim();
  final registryPathOverride =
      optionalStringOption(argResults, 'registry-path')?.trim();
  final registryUrlOverride =
      optionalStringOption(argResults, 'registry-url')?.trim();
  if ((registryPathOverride?.isNotEmpty ?? false) &&
      (registryUrlOverride?.isNotEmpty ?? false)) {
    stderr.writeln(
      'Error: --registry-path and --registry-url cannot be used together.',
    );
    exit(ExitCodes.usage);
  }
  final multiRegistry = MultiRegistryManager(
    targetDir: targetDir,
    offline: offline,
    skipIntegrity: optionalBoolOption(argResults, 'skip-integrity'),
    logger: logger,
    directoryUrl: defaultRegistriesDirectoryUrl,
    directoryPath: registriesPath?.isNotEmpty == true ? registriesPath : null,
    registryPathOverride:
        registryPathOverride?.isNotEmpty == true ? registryPathOverride : null,
    registryUrlOverride:
        registryUrlOverride?.isNotEmpty == true ? registryUrlOverride : null,
  );
  try {
    // Auto-check for updates (rate-limited to once per 24 hours)
    // Skip for version and upgrade commands to avoid recursion
    final shouldCheckUpdates = config.checkUpdates ?? true;
    final commandName = argResults.command?.name;
    if (shouldCheckUpdates &&
        !offline &&
        commandName != 'version' &&
        commandName != 'upgrade') {
      final versionMgr = VersionManager(logger: logger);
      // Run in background without blocking
      unawaited(versionMgr.autoCheckForUpdates());
    }

    final routeDecision = await resolveBootstrapRouteDecision(
      argResults: argResults,
      config: config,
      multiRegistry: multiRegistry,
      registriesUrl: null,
      registriesPath: registriesPath,
    );
    final routeInitToMultiRegistry = routeDecision.routeInitToMultiRegistry;
    final routeAddToMultiRegistry = routeDecision.routeAddToMultiRegistry;

    if (argResults.command!.name == 'doctor') {
      final doctorCommand = argResults.command!;
      if (doctorCommand['help'] == true) {
        print('Usage: flutter_shadcn doctor');
        print('');
        print('Diagnostics for registry resolution and environment.');
        return;
      }
      final doctorExit = await runDoctorCommand(roots, argResults, config);
      if (doctorExit != ExitCodes.success) {
        exitCode = doctorExit;
      }
      return;
    }

    if (argResults.command!.name == 'docs') {
      final cliRoot = roots.cliRoot ?? await packageRoot();
      final docsExit = await runDocsCommand(
        command: argResults.command!,
        cliRoot: cliRoot,
        logger: logger,
      );
      if (docsExit == ExitCodes.ioError) {
        stderr.writeln('Error: Unable to resolve CLI root.');
      }
      if (docsExit != ExitCodes.success) {
        exit(docsExit);
      }
      return;
    }

    if (_isThemeHelpRequest(argResults)) {
      final themeExit = await runThemeCommand(
        themeCommand: argResults.command!,
        rootArgs: argResults,
        installer: null,
        registrySupportsTheme: null,
      );
      if (themeExit != ExitCodes.success) {
        exitCode = themeExit;
      }
      return;
    }

    final commandNamespaceOverride =
        resolveCommandNamespaceOverride(argResults);
    Registry? registry;
    RegistrySelection? preloadedSelection;
    try {
      final preloaded = await preloadRegistryIfNeeded(
        argResults: argResults,
        roots: roots,
        config: config,
        offline: offline,
        routeInitToMultiRegistry: routeInitToMultiRegistry,
        routeAddToMultiRegistry: routeAddToMultiRegistry,
        namespaceOverride: commandNamespaceOverride,
        logger: logger,
      );
      if (preloaded != null) {
        registry = preloaded.registry;
        preloadedSelection = preloaded.selection;
      }
    } on RegistryBootstrapException catch (e) {
      if (e.exitCode() == ExitCodes.usage) {
        stderr.writeln('Error: ${e.message}');
      } else {
        stderr.writeln('Error loading registry: ${e.message}');
        stderr.writeln('Registry root: ${e.registryRoot}');
      }
      exit(e.exitCode());
    }

    final installer = registry == null
        ? null
        : Installer(
            registry: registry,
            targetDir: targetDir,
            logger: logger,
            registryNamespace: preloadedSelection?.namespace,
            registryBaseUrlOverride: preloadedSelection?.sourceRoot.root,
            themesPathOverride: preloadedSelection?.themesPath,
            themesSchemaPathOverride: preloadedSelection?.themesSchemaPath,
            themeConverterDartPathOverride:
                preloadedSelection?.themeConverterDartPath,
            enableSharedGroups:
                preloadedSelection?.capabilitySharedGroups ?? true,
            enableComposites: preloadedSelection?.capabilityComposites ?? true,
          );

    final command = argResults.command!;
    final dispatcher = CommandDispatcher({
      'registries': () => runRegistriesCommand(
            command: command,
            config: config,
            multiRegistry: multiRegistry,
          ),
      'default': () async {
        final result = await runDefaultCommand(
          command: command,
          config: config,
          multiRegistry: multiRegistry,
        );
        config = result.config;
        return result.exitCode;
      },
      'init': () => runInitCommand(
            initCommand: command,
            multiRegistry: multiRegistry,
            defaultNamespace: config.effectiveDefaultNamespace,
          ),
      'theme': () => runThemeCommand(
            themeCommand: command,
            rootArgs: argResults,
            installer: installer,
            registrySupportsTheme: preloadedSelection?.capabilityTheme,
          ),
      'add': () => runAddCommand(
            addCommand: command,
            multiRegistry: multiRegistry,
          ),
      'dry-run': () => runDryRunCommand(
            dryRunCommand: command,
            installer: installer,
          ),
      'remove': () => runRemoveCommand(
            removeCommand: command,
            installer: installer,
            multiRegistry: multiRegistry,
            rootArgs: argResults,
            config: config,
            preloadedNamespace: preloadedSelection?.namespace,
            logger: logger,
          ),
      'validate': () => runValidateCommandCli(
            command: command,
            registry: registry,
            offline: offline,
            logger: logger,
          ),
      'audit': () => runAuditCommandCli(
            command: command,
            registry: registry,
            targetDir: targetDir,
            config: config,
            logger: logger,
          ),
      'deps': () => runDepsCommandCli(
            command: command,
            registry: registry,
            targetDir: targetDir,
            config: config,
            logger: logger,
          ),
      'assets': () => runAssetsCommand(
            command: command,
            installer: installer,
            multiRegistry: multiRegistry,
            rootArgs: argResults,
            config: config,
            logger: logger,
          ),
      'platform': () async {
        final platformResult = await runPlatformCommand(
          command: command,
          config: config,
          targetDir: targetDir,
        );
        config = platformResult.config;
        return platformResult.exitCode;
      },
      'sync': () => runSyncCommand(
            command: command,
            installer: installer,
          ),
      'list': () => runListCommand(
            listCommand: command,
            rootArgs: argResults,
            localRegistryRoot: roots.localRegistryRoot,
            cliRoot: roots.cliRoot,
            config: config,
            offline: offline,
            logger: logger,
          ),
      'search': () => runSearchCommand(
            searchCommand: command,
            rootArgs: argResults,
            localRegistryRoot: roots.localRegistryRoot,
            cliRoot: roots.cliRoot,
            config: config,
            offline: offline,
            logger: logger,
          ),
      'info': () => runInfoCommand(
            infoCommand: command,
            rootArgs: argResults,
            localRegistryRoot: roots.localRegistryRoot,
            cliRoot: roots.cliRoot,
            config: config,
            offline: offline,
            logger: logger,
          ),
      'install-skill': () async {
        final selection =
            resolveRegistrySelection(argResults, roots, config, offline);
        final defaultSkillsUrl = config.registryUrl?.isNotEmpty == true
            ? config.registryUrl!
            : selection.sourceRoot.root;
        return runInstallSkillCommand(
          command: command,
          targetDir: targetDir,
          defaultSkillsUrl: defaultSkillsUrl,
          bundledSkillsPath: roots.cliRoot == null
              ? null
              : p.join(roots.cliRoot!, 'registry', 'skills'),
          logger: logger,
        );
      },
      'version': () => runVersionCommand(
            command: command,
            logger: logger,
          ),
      'upgrade': () => runUpgradeCommand(
            command: command,
            logger: logger,
          ),
      'feedback': () => runFeedbackCommand(
            command: command,
            rootArgs: argResults,
            logger: logger,
            resolveRegistry: (namespaceOverride) {
              final selection = resolveRegistrySelection(
                argResults,
                roots,
                config,
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
    final dispatchExit = await dispatcher.dispatch(command.name!);
    if (dispatchExit != ExitCodes.success) {
      exitCode = dispatchExit;
    }
  } finally {
    multiRegistry.close();
  }
}

void _ensureExecutablePath() {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    return;
  }
  final pubBin = p.join(home, '.pub-cache', 'bin');
  final pathEntries = (Platform.environment['PATH'] ?? '').split(':');
  if (pathEntries.contains(pubBin)) {
    return;
  }
  final target = p.join(pubBin, 'flutter_shadcn');
  final linkPath = '/usr/local/bin/flutter_shadcn';
  if (!File(target).existsSync()) {
    return;
  }
  final link = Link(linkPath);
  try {
    if (link.existsSync()) {
      return;
    }
    link.createSync(target);
  } catch (_) {
    return;
  }
}

String? _advancedGateError(ArgResults argResults, bool advanced) {
  if (advanced) {
    return null;
  }
  final commandName = argResults.command?.name;
  if (commandName == 'docs' || commandName == 'install-skill') {
    return 'The $commandName command requires --advanced.';
  }
  for (final name in const [
    'registry-path',
    'registry-url',
    'registries-path',
    'skip-integrity',
  ]) {
    if (argResults.wasParsed(name)) {
      return 'The --$name flag requires --advanced.';
    }
  }
  return null;
}

bool _isThemeHelpRequest(ArgResults argResults) {
  final command = argResults.command;
  if (command?.name != 'theme') {
    return false;
  }
  if (command?['help'] == true) {
    return true;
  }
  return command?.command?.name == 'widget' &&
      command?.command?['help'] == true;
}
