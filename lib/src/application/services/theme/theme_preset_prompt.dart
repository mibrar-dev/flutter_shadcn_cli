import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/theme/theme_models.dart';

/// Interactive preset picker shared by a bare `theme` run and by `init`.
///
/// The readers/writers are injectable so the picker can be tested without a
/// terminal; the defaults are the process stdin/stdout.
Future<ThemeCatalogEntry?> promptForThemePreset(
  List<ThemeCatalogEntry> presets, {
  required String question,
  String? Function()? readLine,
  void Function(String message)? write,
}) async {
  if (presets.isEmpty) return null;
  final read = readLine ?? () => stdin.readLineSync();
  final out = write ?? stdout.write;
  for (var i = 0; i < presets.length; i++) {
    final preset = presets[i];
    final current = preset.isCurrent ? ' (current)' : '';
    out('  ${i + 1}) ${preset.name} (${preset.id})$current\n');
  }
  out(question);
  final answer = read()?.trim();
  if (answer == null || answer.isEmpty) return null;

  final index = int.tryParse(answer);
  if (index != null) {
    if (index < 1 || index > presets.length) return null;
    return presets[index - 1];
  }
  final needle = answer.toLowerCase();
  for (final preset in presets) {
    if (preset.id.toLowerCase() == needle ||
        preset.name.toLowerCase() == needle) {
      return preset;
    }
  }
  return null;
}
