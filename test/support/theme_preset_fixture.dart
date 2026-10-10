import 'package:flutter_shadcn_cli/src/application/services/theme/app_theme_values.dart';

/// Builds a schemaVersion 2 preset document for tests.
///
/// Starts from the 32 colour tokens the schema requires and lets a test tweak
/// one block at a time, so a "valid preset" never drifts from the token list.
Map<String, dynamic> themePresetJson({
  String id = 'fixture-preset',
  String name = 'Fixture Preset',
  bool includeFonts = true,
  bool includeTracking = true,
}) {
  final colors = <String, String>{
    for (final key in appThemeColorTokenKeys)
      key: key == 'border' || key == 'sidebarBorder' ? '#E0E0E0' : '#FFFFFF',
  };
  return <String, dynamic>{
    r'$schema': './themes.schema.json',
    'id': id,
    'name': name,
    'schemaVersion': 2,
    'light': Map<String, dynamic>.of(colors),
    'dark': Map<String, dynamic>.of(colors),
    if (includeFonts)
      'fonts': <String, dynamic>{
        'sans': 'Inter, sans-serif',
        'mono': 'JetBrains Mono, monospace',
      },
    'radius': 0.5,
    'spacing': 0.25,
    if (includeTracking) 'tracking': <String, dynamic>{'normal': 0},
    'shadow': <String, dynamic>{
      'light': _shadow(),
      'dark': _shadow(),
    },
    'shadowsDerived': 'cli',
  };
}

Map<String, dynamic> _shadow() => <String, dynamic>{
      'color': '#000000',
      'opacity': 0.1,
      'blur': 2,
      'spread': 0,
      'offsetX': 0,
      'offsetY': 1,
    };
