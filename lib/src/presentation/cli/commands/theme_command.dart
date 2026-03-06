import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/installer.dart';

Future<int> runThemeCommand({
  required ArgResults themeCommand,
  required ArgResults rootArgs,
  required Installer? installer,
  required bool? registrySupportsTheme,
}) async {
  final activeInstaller = installer;
  if (activeInstaller == null) {
    stderr.writeln('Error: Installer is not available.');
    return ExitCodes.registryNotFound;
  }
  final widgetCommand = themeCommand.command;
  if (widgetCommand?.name == 'widget') {
    return _runWidgetThemeCommand(
      widgetCommand: widgetCommand!,
      installer: activeInstaller,
    );
  }
  if (themeCommand['help'] == true) {
    print(
        'Usage: flutter_shadcn theme [--list | --apply <preset> | --apply-file <path> | --apply-url <url>] [--refresh]');
    print(
        '       flutter_shadcn theme widget [@namespace] <component> [--list-targets | --apply-file <path> | --apply-url <url> | --reset]');
    print('');
    print('Options:');
    print('  --list             Show all available theme presets');
    print('  --refresh          Refresh theme cache');
    print('  --apply, -a <id>   Apply the preset with the given ID');
    print('  --apply-file       Apply a theme JSON file (experimental)');
    print('  --apply-url        Apply a theme JSON URL (experimental)');
    print('  --help, -h         Show this message');
    print('');
    print('Experimental:');
    print('  Use --experimental to enable apply-file/apply-url.');
    return ExitCodes.success;
  }
  if (registrySupportsTheme == false) {
    print('This registry does not provide theme presets.');
    return ExitCodes.success;
  }
  final isExperimental = rootArgs['experimental'] == true;
  final refresh = themeCommand['refresh'] == true;
  if (themeCommand['list'] == true) {
    await activeInstaller.listThemes(refresh: refresh);
    return ExitCodes.success;
  }
  final applyFile = themeCommand['apply-file'] as String?;
  final applyUrl = themeCommand['apply-url'] as String?;
  if (applyFile != null || applyUrl != null) {
    if (!isExperimental) {
      stderr.writeln('Error: --apply-file/--apply-url require --experimental.');
      return ExitCodes.usage;
    }
    if (applyFile != null) {
      await activeInstaller.applyThemeFromFile(applyFile);
      return ExitCodes.success;
    }
    if (applyUrl != null) {
      await activeInstaller.applyThemeFromUrl(applyUrl);
      return ExitCodes.success;
    }
  }
  final applyOption = themeCommand['apply'] as String?;
  final rest = [...themeCommand.rest];
  if (rest.isNotEmpty &&
      rest.first.startsWith('@') &&
      !rest.first.contains('/')) {
    rest.removeAt(0);
  }
  final presetArg = applyOption ?? (rest.isEmpty ? null : rest.first);
  if (presetArg != null) {
    await activeInstaller.applyThemeById(presetArg, refresh: refresh);
    return ExitCodes.success;
  }
  await activeInstaller.chooseTheme(refresh: refresh);
  return ExitCodes.success;
}

Future<int> _runWidgetThemeCommand({
  required ArgResults widgetCommand,
  required Installer installer,
}) async {
  if (widgetCommand['help'] == true) {
    print(
        'Usage: flutter_shadcn theme widget [@namespace] <component> [--list-targets | --apply-file <path> | --apply-url <url> | --reset]');
    print('');
    print('Options:');
    print(
        '  --list               Show all themeable widgets in the active registry');
    print(
        '  --list-targets       Show available theme targets for the selected widget');
    print('  --apply-file <path>  Apply widget theme from a local JSON file');
    print('  --apply-url <url>    Apply widget theme from a JSON URL');
    print(
        '  --reset              Reset widget theme overrides for the selected widget');
    print('  --help, -h           Show this message');
    return ExitCodes.success;
  }

  if (widgetCommand['list'] == true) {
    await installer.listWidgetThemes();
    return ExitCodes.success;
  }

  final rest = [...widgetCommand.rest];
  if (rest.isNotEmpty &&
      rest.first.startsWith('@') &&
      !rest.first.contains('/')) {
    rest.removeAt(0);
  }
  final component = rest.isEmpty ? null : rest.first;
  if (component == null || component.trim().isEmpty) {
    stderr.writeln(
      'Error: Widget component is required. Use "flutter_shadcn theme widget --list" to browse themeable widgets.',
    );
    return ExitCodes.usage;
  }

  if (widgetCommand['list-targets'] == true) {
    await installer.listWidgetThemeTargets(component);
    return ExitCodes.success;
  }

  final applyFile = widgetCommand['apply-file'] as String?;
  if (applyFile != null) {
    await installer.applyWidgetThemeFromFile(component, applyFile);
    return ExitCodes.success;
  }

  final applyUrl = widgetCommand['apply-url'] as String?;
  if (applyUrl != null) {
    await installer.applyWidgetThemeFromUrl(component, applyUrl);
    return ExitCodes.success;
  }

  if (widgetCommand['reset'] == true) {
    await installer.resetWidgetTheme(component);
    return ExitCodes.success;
  }

  stderr.writeln(
    'Error: No widget theme action provided. Use --list-targets, --apply-file, --apply-url, or --reset.',
  );
  return ExitCodes.usage;
}
