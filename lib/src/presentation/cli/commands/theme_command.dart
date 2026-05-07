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
  final advanced = rootArgs['advanced'] == true;
  final widgetCommand = themeCommand.command;
  if (themeCommand['help'] == true) {
    _printThemeHelp(advanced: advanced);
    return ExitCodes.success;
  }
  if (widgetCommand?.name == 'widget' && widgetCommand?['help'] == true) {
    _printWidgetThemeHelp(advanced: advanced);
    return ExitCodes.success;
  }
  final activeInstaller = installer;
  if (activeInstaller == null) {
    stderr.writeln('Error: Installer is not available.');
    return ExitCodes.registryNotFound;
  }
  if (widgetCommand?.name == 'widget') {
    return _runWidgetThemeCommand(
      widgetCommand: widgetCommand!,
      installer: activeInstaller,
      advanced: advanced,
    );
  }
  final refresh = themeCommand['refresh'] == true;
  final applyFile = themeCommand['apply-file'] as String?;
  final applyUrl = themeCommand['apply-url'] as String?;
  if (applyFile != null || applyUrl != null) {
    if (!advanced) {
      stderr.writeln('Error: --apply-file/--apply-url require --advanced.');
      return ExitCodes.usage;
    }
    if (applyFile != null) {
      return _runThemeAction(
          () => activeInstaller.applyThemeFromFile(applyFile));
    }
    if (applyUrl != null) {
      return _runThemeAction(() => activeInstaller.applyThemeFromUrl(applyUrl));
    }
  }
  if (registrySupportsTheme == false) {
    print('This registry does not provide theme presets.');
    return ExitCodes.success;
  }
  if (themeCommand['list'] == true) {
    return _runThemeAction(() => activeInstaller.listThemes(refresh: refresh));
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
    return _runThemeAction(
      () => activeInstaller.applyThemeById(presetArg, refresh: refresh),
    );
  }
  return _runThemeAction(() => activeInstaller.chooseTheme(refresh: refresh));
}

Future<int> _runWidgetThemeCommand({
  required ArgResults widgetCommand,
  required Installer installer,
  required bool advanced,
}) async {
  if (widgetCommand['list'] == true) {
    return _runThemeAction(installer.listWidgetThemes);
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
    return _runThemeAction(() => installer.listWidgetThemeTargets(component));
  }

  final applyFile = widgetCommand['apply-file'] as String?;
  final applyUrl = widgetCommand['apply-url'] as String?;
  if ((applyFile != null || applyUrl != null) && !advanced) {
    stderr.writeln('Error: --apply-file/--apply-url require --advanced.');
    return ExitCodes.usage;
  }
  if (applyFile != null) {
    return _runThemeAction(
      () => installer.applyWidgetThemeFromFile(component, applyFile),
    );
  }
  if (applyUrl != null) {
    return _runThemeAction(
      () => installer.applyWidgetThemeFromUrl(component, applyUrl),
    );
  }

  if (widgetCommand['reset'] == true) {
    return _runThemeAction(() => installer.resetWidgetTheme(component));
  }

  stderr.writeln(
    'Error: No widget theme action provided. Use --list-targets, --apply-file, --apply-url, or --reset.',
  );
  return ExitCodes.usage;
}

Future<int> _runThemeAction(Future<void> Function() action) async {
  try {
    await action();
    return ExitCodes.success;
  } on UnsupportedError catch (error) {
    stderr.writeln('Error: ${error.message}');
    return ExitCodes.validationFailed;
  } on FormatException catch (error) {
    stderr.writeln('Error: ${error.message}');
    return ExitCodes.validationFailed;
  } catch (error) {
    stderr.writeln('Error: ${_formatThemeError(error)}');
    return ExitCodes.validationFailed;
  }
}

String _formatThemeError(Object error) {
  final message = error.toString();
  const exceptionPrefix = 'Exception: ';
  if (message.startsWith(exceptionPrefix)) {
    return message.substring(exceptionPrefix.length);
  }
  return message;
}

void _printThemeHelp({required bool advanced}) {
  if (advanced) {
    print(
        'Usage: flutter_shadcn theme [--list | --apply <preset> | --apply-file <path> | --apply-url <url>] [--refresh]');
    print(
        '       flutter_shadcn theme widget [@namespace] <component> [--list-targets | --apply-file <path> | --apply-url <url> | --reset]');
  } else {
    print(
        'Usage: flutter_shadcn theme [--list | --apply <preset>] [--refresh]');
    print(
        '       flutter_shadcn theme widget [@namespace] <component> [--list-targets | --reset]');
  }
  print('');
  print('Options:');
  print('  --list             Show all available theme presets');
  print('  --refresh          Refresh theme cache');
  print('  --apply, -a <id>   Apply the preset with the given ID');
  if (advanced) {
    print('  --apply-file       Apply a declarative theme manifest file');
    print('  --apply-url        Apply a declarative theme manifest URL');
  }
  print('  --help, -h         Show this message');
}

void _printWidgetThemeHelp({required bool advanced}) {
  if (advanced) {
    print(
        'Usage: flutter_shadcn theme widget [@namespace] <component> [--list-targets | --apply-file <path> | --apply-url <url> | --reset]');
  } else {
    print(
        'Usage: flutter_shadcn theme widget [@namespace] <component> [--list-targets | --reset]');
  }
  print('');
  print('Options:');
  print(
      '  --list               Show all themeable widgets in the active registry');
  print(
      '  --list-targets       Show available theme targets for the selected widget');
  if (advanced) {
    print('  --apply-file <path>  Apply widget theme from a local JSON file');
    print('  --apply-url <url>    Apply widget theme from a JSON URL');
  }
  print(
      '  --reset              Reset widget theme overrides for the selected widget');
  print('  --help, -h           Show this message');
}
