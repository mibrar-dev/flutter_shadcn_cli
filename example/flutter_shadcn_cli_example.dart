import 'package:flutter_shadcn_cli/flutter_shadcn_cli.dart';

void main() {
  final presets = registryThemePresetsData;
  final firstPreset = presets.first;

  print('Bundled theme presets: ${presets.length}');
  print('First preset: ${firstPreset.name} (${firstPreset.id})');
  print('Light primary: ${firstPreset.light['primary']}');
  print('Dark primary: ${firstPreset.dark['primary']}');

  RegistryThemePresetData? modernMinimal;
  for (final preset in presets) {
    if (preset.id == 'modern-minimal') {
      modernMinimal = preset;
      break;
    }
  }

  if (modernMinimal != null) {
    print('Modern Minimal radius: ${modernMinimal.lightTokens['radius']}');
  }
}
