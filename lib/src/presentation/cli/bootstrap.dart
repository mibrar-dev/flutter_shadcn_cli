import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_shadcn_cli/src/installer.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry_directory.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/multi_registry_manager.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/bootstrap_dispatcher_builder.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/docs_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/arg_helpers.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/theme_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands_doctor.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/registry_selection.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/runtime_roots.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/bootstrap_support.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/registry_bootstrap_exception.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/usage.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/version_manager.dart';
import 'package:flutter_shadcn_cli/src/application/services/reset/reset_snapshot_store.dart';

Future<void> runCliBootstrap(List<String> arguments) async {
  _ensureExecutablePath();
  final homeDirectory = _userHomeDirectory();
  if (homeDirectory != null && homeDirectory.isNotEmpty) {
    try {
      await ResetSnapshotStore(
        homeDirectory: homeDirectory,
      ).pruneExpiredSnapshots();
    } catch (_) {}
  }
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
  if (argResults['version'] == true) {
    VersionManager(
      logger: CliLogger(verbose: argResults['verbose'] == true),
    ).showVersion();
    exit(ExitCodes.success);
  }
  if (_isProjectHelpArgs(normalizedArgs)) {
    _printProjectUsage();
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
      optionalStringOption(argResults, 'registries-path')?.trim() ??
          config.registriesPath?.trim();
  final registryPathOverride = optionalStringOption(
    argResults,
    'registry-path',
  )?.trim();
  final registryUrlOverride = optionalStringOption(
    argResults,
    'registry-url',
  )?.trim();
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

    if (_isCommandHelpRequest(argResults)) {
      final command = argResults.command!;
      final dispatcher = buildBootstrapCommandDispatcher(
        rootArgs: argResults,
        command: command,
        roots: roots,
        targetDir: targetDir,
        homeDirectory: homeDirectory,
        offline: offline,
        logger: logger,
        multiRegistry: multiRegistry,
        installer: null,
        preloadedSelection: null,
        readConfig: () => config,
        writeConfig: (updatedConfig) {
          config = updatedConfig;
        },
      );
      final dispatchExit = await dispatcher.dispatch(command.name!);
      if (dispatchExit != ExitCodes.success) {
        exitCode = dispatchExit;
      }
      return;
    }

    final commandNamespaceOverride = resolveCommandNamespaceOverride(
      argResults,
    );
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
      final failedCommand = argResults.command?.name;
      final wantsJson = argResults.command?['json'] == true;
      if (wantsJson &&
          (failedCommand == 'validate' ||
              failedCommand == 'audit' ||
              failedCommand == 'deps')) {
        // Mirror doctor --json: proper JSON error envelope on STDOUT,
        // diagnostics stay parseable instead of stderr-only text.
        final code = e.exitCode();
        printJson(jsonEnvelope(
          command: failedCommand!,
          data: const {},
          errors: [
            jsonError(
              code: _exitCodeLabelFor(code),
              message: 'Error loading registry: ${e.message}',
              details: {'registryRoot': e.registryRoot},
            ),
          ],
          meta: {'exitCode': code},
        ));
        exit(code);
      }
      if (e.exitCode() == ExitCodes.usage) {
        stderr.writeln('Error: ${e.message}');
      } else {
        stderr.writeln('Error loading registry: ${e.message}');
        stderr.writeln('Registry root: ${e.registryRoot}');
      }
      if (failedCommand == 'info') {
        // Best effort only: `info` can still answer from index.json, so
        // continue without manifest-backed import paths instead of failing.
        stderr.writeln(
          'Warning: continuing without registry manifest data.',
        );
      } else {
        exit(e.exitCode());
      }
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
            enableSharedGroups:
                preloadedSelection?.capabilitySharedGroups ?? true,
            enableComposites: preloadedSelection?.capabilityComposites ?? true,
          );

    final command = argResults.command!;
    final dispatcher = buildBootstrapCommandDispatcher(
      rootArgs: argResults,
      command: command,
      roots: roots,
      targetDir: targetDir,
      homeDirectory: homeDirectory,
      offline: offline,
      logger: logger,
      multiRegistry: multiRegistry,
      installer: installer,
      preloadedSelection: preloadedSelection,
      readConfig: () => config,
      writeConfig: (updatedConfig) {
        config = updatedConfig;
      },
    );
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

String? _userHomeDirectory() {
  final env = Platform.environment;
  if (Platform.isWindows) {
    return env['USERPROFILE'] ?? env['HOME'];
  }
  return env['HOME'];
}

String? _advancedGateError(ArgResults argResults, bool advanced) {
  if (advanced) {
    return null;
  }
  final commandName = argResults.command?.name;
  if (commandName == 'docs') {
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

bool _isCommandHelpRequest(ArgResults argResults) {
  final command = argResults.command;
  if (command == null) {
    return false;
  }
  if (command['help'] == true) {
    return true;
  }
  if (command.rest.contains('--help') || command.rest.contains('-h')) {
    return true;
  }
  final nested = command.command;
  return nested != null && nested['help'] == true;
}

bool _isProjectHelpArgs(List<String> arguments) {
  if (arguments.length != 2 || arguments.first != 'project') {
    return false;
  }
  return arguments[1] == '--help' || arguments[1] == '-h';
}

void _printProjectUsage() {
  print('Usage: flutter_shadcn project <command>');
  print('');
  print('Commands:');
  print(
      '  reset [--undo]     Remove CLI-managed project files or restore them');
  print('  refresh            Regenerate missing CLI scaffolding');
}

String _exitCodeLabelFor(int code) {
  switch (code) {
    case ExitCodes.registryNotFound:
      return ExitCodeLabels.registryNotFound;
    case ExitCodes.schemaInvalid:
      return ExitCodeLabels.schemaInvalid;
    case ExitCodes.offlineUnavailable:
      return ExitCodeLabels.offlineUnavailable;
    case ExitCodes.networkError:
      return ExitCodeLabels.networkError;
    case ExitCodes.configInvalid:
      return ExitCodeLabels.configInvalid;
    case ExitCodes.validationFailed:
      return ExitCodeLabels.validationFailed;
    case ExitCodes.usage:
      return ExitCodeLabels.usage;
    default:
      return ExitCodeLabels.unknown;
  }
}
