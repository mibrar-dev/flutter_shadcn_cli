import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_models.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_preset_prompt.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_service.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/installer.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';

/// `flutter_shadcn theme list` and `flutter_shadcn theme apply <preset>`.
///
/// Both actions read the preset catalogue from the manifest `themes` map and
/// render `themes/<id>.json` into `<installRoot>/theme/app_theme.dart` through
/// [ThemeService]; the command only parses arguments and prints.
///
/// Argument shapes accepted (the parser is owned by another batch, so every
/// form is probed defensively):
///
/// ```
/// theme list [--json]
/// theme apply <preset> [--refresh] [--json]
/// theme --list | theme --apply <preset> | theme <preset>   (legacy flags)
/// theme                                                 (interactive picker)
/// ```
Future<int> runThemeCommand({
  required ArgResults themeCommand,
  required ArgResults rootArgs,
  required Installer? installer,
  required bool? registrySupportsTheme,
}) async {
  if (_flag(themeCommand, 'help') == true ||
      _sub(themeCommand, 'help') != null) {
    _printThemeHelp();
    return ExitCodes.success;
  }
  final sub = themeCommand.command;
  if (sub != null && sub.name != 'list' && sub.name != 'apply') {
    stderr.writeln(
      'Error: "theme ${sub.name}" was removed with the v1 theme manifest. '
      'Use "theme list" or "theme apply <preset>".',
    );
    return ExitCodes.usage;
  }
  final refresh = _flag(themeCommand, 'refresh') == true ||
      (sub != null && _flag(sub, 'refresh') == true);
  final json = _flag(themeCommand, 'json') == true ||
      (sub != null && _flag(sub, 'json') == true);
  if (_option(themeCommand, 'apply-file') != null ||
      _option(themeCommand, 'apply-url') != null) {
    stderr.writeln(
      'Error: --apply-file/--apply-url were removed. A preset is applied by id: '
      '"theme apply <preset>".',
    );
    return ExitCodes.usage;
  }
  if (registrySupportsTheme == false) {
    print('This registry does not provide theme presets.');
    return ExitCodes.success;
  }

  // Warnings must never pollute stdout when --json is in play.
  final logger = CliLogger(
    verbose: _flag(rootArgs, 'verbose') == true,
    useColor: !json,
    writeLine: json ? stderr.writeln : stdout.writeln,
    writeStderrLine: stderr.writeln,
  );
  final projectRoot = installer?.projectRoot ?? Directory.current.path;

  try {
    final service = await ThemeService.resolve(
      projectRoot: projectRoot,
      installRoot: installer?.installRoot,
      namespace: _option(rootArgs, 'registry-name'),
      registryPathOverride: _option(rootArgs, 'registry-path'),
      registryUrlOverride: _option(rootArgs, 'registry-url'),
      offline: _flag(rootArgs, 'offline') == true,
      logger: logger,
    );

    final presetId = _resolvePresetId(themeCommand, sub);
    final wantsList = _flag(themeCommand, 'list') == true ||
        sub?.name == 'list' ||
        (presetId == null && json);

    if (presetId != null) {
      final result = await service.apply(presetId, refresh: refresh);
      if (json) {
        print(jsonEncode(<String, Object?>{'applied': result.toJson()}));
      }
      return result.isClean ? ExitCodes.success : ExitCodes.validationFailed;
    }
    if (wantsList) {
      return await _printCatalog(await service.listPresets(), json: json);
    }
    return await _chooseInteractively(service);
  } catch (error) {
    return _themeFailure(error);
  }
}

Future<int> _printCatalog(
  List<ThemeCatalogEntry> presets, {
  required bool json,
}) async {
  if (json) {
    print(
      jsonEncode(<String, Object?>{
        'presets': presets.map((preset) => preset.toJson()).toList(),
        'current': presets.any((p) => p.isCurrent)
            ? presets.firstWhere((p) => p.isCurrent).id
            : null,
      }),
    );
    return ExitCodes.success;
  }
  if (presets.isEmpty) {
    print('No theme presets available in this registry.');
    return ExitCodes.success;
  }
  print('Available theme presets (${presets.length}):');
  for (final preset in presets) {
    final current = preset.isCurrent ? '  (current)' : '';
    print('  ${preset.id.padRight(20)} ${preset.name}'
        '  [${preset.modes.join(', ')}]$current');
  }
  print('');
  print('Apply one with: flutter_shadcn theme apply <preset>');
  return ExitCodes.success;
}

Future<int> _chooseInteractively(ThemeService service) async {
  final presets = await service.listPresets();
  if (presets.isEmpty) {
    print('No theme presets available in this registry.');
    return ExitCodes.success;
  }
  print('Select a theme preset (press Enter to skip):');
  final chosen = await promptForThemePreset(
    presets,
    question: 'Theme number: ',
  );
  if (chosen == null) {
    print('Skipping theme selection.');
    return ExitCodes.success;
  }
  final result = await service.apply(chosen.id);
  return result.isClean ? ExitCodes.success : ExitCodes.validationFailed;
}

/// The preset id from `theme apply <id>`, `theme --apply <id>`, a leading
/// `@namespace` token or a bare `theme <id>`.
String? _resolvePresetId(ArgResults args, ArgResults? sub) {
  final option = _option(args, 'apply') ??
      (sub != null && sub.name == 'apply' ? _option(sub, 'apply') : null);
  if (option != null && option.trim().isNotEmpty) return option.trim();
  if (sub != null && sub.rest.isNotEmpty) {
    return _firstPresetToken(sub.rest);
  }
  return _firstPresetToken(args.rest);
}

String? _firstPresetToken(List<String> rest) {
  for (final token in rest) {
    final value = token.trim();
    if (value.isEmpty) continue;
    if (value.startsWith('@') && !value.contains('/')) continue;
    return value;
  }
  return null;
}

int _themeFailure(Object error) {
  if (error is ThemeApplyException) {
    if (error.message.startsWith('No shadcn registry is configured')) {
      return ExitCodes.registryNotFound;
    }
    for (final line in error.lines) {
      stderr.writeln('Error: $line');
    }
    return ExitCodes.validationFailed;
  }
  if (error is FormatException) {
    stderr.writeln('Error: ${error.message}');
    return ExitCodes.validationFailed;
  }
  stderr.writeln('Error: $error');
  return ExitCodes.ioError;
}

bool? _flag(ArgResults args, String name) {
  try {
    final value = args[name];
    return value is bool ? value : null;
  } on ArgumentError {
    // The option is not registered on this parser; another batch owns it.
    return null;
  }
}

String? _option(ArgResults args, String name) {
  try {
    final value = args[name];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  } on ArgumentError {
    return null;
  }
}

ArgResults? _sub(ArgResults args, String name) {
  final command = args.command;
  return command != null && command.name == name ? command : null;
}

void _printThemeHelp() {
  print('Usage: flutter_shadcn theme list [--json]');
  print('       flutter_shadcn theme apply <preset> [--refresh] [--json]');
  print('       flutter_shadcn theme');
  print('');
  print('Commands:');
  print('  list              Show the presets from the registry manifest');
  print('  apply <preset>    Generate <installRoot>/theme/app_theme.dart');
  print('');
  print('Options:');
  print('  --refresh         Overwrite app_theme.dart even when it was edited');
  print('  --json            Machine-readable output on stdout');
  print('  --help, -h        Show this message');
  print('');
  print(
      'app_theme.dart is yours: without --refresh a locally modified file is');
  print('reported as drift and left untouched.');
  print('');
  print('Legacy flags --apply/-a and --list still work. --apply-file,');
  print('--apply-url and "theme widget" were removed with the v1 theme');
  print('manifest; "theme import <css|json|url>" is not implemented yet.');
}
