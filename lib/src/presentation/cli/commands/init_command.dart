import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_source.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_preset_prompt.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_context.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_support.dart';

/// Preset used by `init --yes` (plan §9.2): neutral black/white, closest to
/// shadcn's default.
const String kDefaultThemePreset = 'vercel';

/// Default install root (plan §2.1).
const String kDefaultInstallRoot = 'lib/ui/shadcn';

/// `flutter_shadcn init [--dir <path>] [--theme <id>] [--yes] [--json]`
/// (P5_CLI_PLAN.md §2.1).
///
/// Installs the always-on foundation + theme core, writes `.shadcn/config.json`
/// and generates `<installRoot>/theme/app_theme.dart` from the chosen preset.
/// It never installs a component.
Future<int> runInitCommand({
  required ArgResults initCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(initCommand, 'json');
  final logger = commandLogger(rootArgs, json: json);

  if (commandFlag(initCommand, 'help')) {
    _printInitHelp();
    return ExitCodes.success;
  }

  final assumeYes = commandFlag(initCommand, 'yes');
  final targetDir = commandOption(initCommand, 'dir') ?? kDefaultInstallRoot;
  final requestedTheme = commandOption(initCommand, 'theme');

  try {
    final context = await CommandContextResolver.resolve(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      installRootOverride: targetDir,
      offline: offline,
    );

    final coreReport = await context.installer.installCore();
    final themeId = await _chooseTheme(
      context: context,
      requested: requestedTheme,
      assumeYes: assumeYes,
      json: json,
    );
    await _writeConfig(context, themeId);
    final themeResult = await context.themeService.apply(themeId);

    if (json) {
      printJson(jsonEnvelope(
        command: 'init',
        data: {
          'installRoot': context.installRoot,
          'theme': themeResult.toJson(),
          'core': coreReport.toJson(),
        },
        meta: {'exitCode': ExitCodes.success},
      ));
      return ExitCodes.success;
    }

    logger.header('Initialized shadcn_flutter');
    logger.info('  install root: ${context.installRoot}');
    logger.info('  theme:        ${themeResult.presetName} '
        '(${themeResult.path})');
    if (coreReport.packagesAdded.isNotEmpty) {
      logger.info('  packages:     ${coreReport.packagesAdded.join(', ')}');
    }
    logger.info('');
    logger.info('Next: flutter_shadcn add button');
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}

Future<String> _chooseTheme({
  required CommandContext context,
  required String? requested,
  required bool assumeYes,
  required bool json,
}) async {
  final trimmed = requested?.trim();
  if (trimmed != null && trimmed.isNotEmpty) {
    return trimmed;
  }
  if (assumeYes || json || !stdin.hasTerminal) {
    return kDefaultThemePreset;
  }
  final presets = await context.themeService.listPresets();
  context.logger.info('Select a theme preset (press Enter for '
      '$kDefaultThemePreset):');
  final chosen = await promptForThemePreset(
    presets,
    question: 'Theme number: ',
    write: context.logger.info,
  );
  return chosen?.id ?? kDefaultThemePreset;
}

Future<void> _writeConfig(CommandContext context, String themeId) async {
  final source = context.source;
  final updated = context.config.copyWith(
    installPath: context.installRoot,
    themeId: themeId,
    defaultNamespace: context.config.effectiveDefaultNamespace,
    registryPath: source is LocalRegistrySource ? source.localRoot : null,
    registryUrl: source is RemoteRegistrySource ? source.baseUrl : null,
  );
  await ShadcnConfig.save(context.projectRoot, updated);
}

void _printInitHelp() {
  stdout.writeln('Usage: flutter_shadcn init [flags]');
  stdout.writeln('');
  stdout
      .writeln('Installs the always-on foundation + theme core and generates');
  stdout.writeln('<installRoot>/theme/app_theme.dart from a theme preset.');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
      '  --dir <path>     Install root (default: $kDefaultInstallRoot)');
  stdout.writeln(
      '  --theme <id>     Theme preset id (default: $kDefaultThemePreset)');
  stdout.writeln('  --yes, -y        Non-interactive; use the default preset');
  stdout.writeln('  --json           Machine-readable output on stdout');
  stdout.writeln('  --help, -h       Show this message');
}
