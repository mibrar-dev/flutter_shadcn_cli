import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/resolver/v1/project_path_guard.dart';
import 'package:path/path.dart' as p;

Future<int> runLocaleCommand({
  required ArgResults command,
  required String targetDir,
}) async {
  if (command['help'] == true) {
    _printLocaleHelp();
    return ExitCodes.success;
  }
  final subcommand = command.command;
  if (subcommand == null || subcommand.name != 'init') {
    _printLocaleHelp();
    return ExitCodes.usage;
  }
  if (subcommand['help'] == true) {
    _printLocaleInitHelp();
    return ExitCodes.success;
  }
  return _runLocaleInit(targetDir);
}

Future<int> _runLocaleInit(String targetDir) async {
  final l10nFile = File(
    ProjectPathGuard.resolveSafeWritePath(
      projectRoot: targetDir,
      destinationRelativePath: 'l10n.yaml',
    ),
  );
  if (l10nFile.existsSync()) {
    stderr.writeln('Error: l10n.yaml already exists.');
    return ExitCodes.configInvalid;
  }
  final arbDir = Directory(
    ProjectPathGuard.resolveSafeWritePath(
      projectRoot: targetDir,
      destinationRelativePath: p.join('lib', 'l10n'),
    ),
  );
  if (!arbDir.existsSync()) {
    await arbDir.create(recursive: true);
  }
  await l10nFile.writeAsString('''
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
''');
  final appEn = File(p.join(arbDir.path, 'app_en.arb'));
  if (!appEn.existsSync()) {
    await appEn.writeAsString('{\n  "@@locale": "en"\n}\n');
  }
  stdout.writeln('Created l10n.yaml and lib/l10n/.');
  return ExitCodes.success;
}

void _printLocaleHelp() {
  print('Usage: flutter_shadcn locale <command>');
  print('');
  print('Commands:');
  print('  init              Create l10n.yaml and lib/l10n/');
}

void _printLocaleInitHelp() {
  print('Usage: flutter_shadcn locale init');
  print('');
  print('Creates l10n.yaml and lib/l10n/ for component locale resources.');
}
