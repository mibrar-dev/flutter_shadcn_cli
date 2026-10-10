/// Value model for one canonical theme preset — a port of the parsing half of
/// the kit's `tool/rearch/gen_app_theme.dart` (`ThemeValues` / `ShadowAtoms`).
///
/// A preset is `lib/registry/themes/<id>.json` (schemaVersion 2, see
/// `themes.schema.json` in the registry). This library holds no Flutter
/// import: values stay ARGB ints and Dart numbers, and
/// [AppThemeValues.id]/[AppThemeValues.name] are the only strings that reach
/// the emitted file.
///
/// The emitted source must stay byte-for-byte identical to the kit
/// generator's output; `test/theme/app_theme_golden_test.dart` runs both over
/// the same preset and compares.
library;

/// The 32 colour tokens of `ShadcnColors` in declaration order.
///
/// Kept as data so the emitted argument order matches the constructor and an
/// unknown token in a preset is a hard error instead of a silent omission.
const List<String> appThemeColorTokenKeys = <String>[
  'background',
  'foreground',
  'card',
  'cardForeground',
  'popover',
  'popoverForeground',
  'primary',
  'primaryForeground',
  'secondary',
  'secondaryForeground',
  'muted',
  'mutedForeground',
  'accent',
  'accentForeground',
  'destructive',
  'destructiveForeground',
  'border',
  'input',
  'ring',
  'chart1',
  'chart2',
  'chart3',
  'chart4',
  'chart5',
  'sidebar',
  'sidebarForeground',
  'sidebarPrimary',
  'sidebarPrimaryForeground',
  'sidebarAccent',
  'sidebarAccentForeground',
  'sidebarBorder',
  'sidebarRing',
];

/// Matches the `colorToken` schema pattern (`#RRGGBB` or `#RRGGBBAA`).
final RegExp appThemeHexColorPattern =
    RegExp(r'^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$');

/// Parses `#RRGGBB` / `#RRGGBBAA` into a 32-bit ARGB int.
///
/// The alpha byte defaults to `FF` and is never dropped when present, which
/// is what the legacy presets got wrong for shadcn's 10%-alpha dark border.
int parseAppThemeHexColor(String value) {
  if (!appThemeHexColorPattern.hasMatch(value)) {
    throw FormatException('Not a #RRGGBB[AA] colour: $value');
  }
  final digits = value.substring(1);
  final rgb = int.parse(digits.substring(0, 6), radix: 16);
  final alpha =
      digits.length == 8 ? int.parse(digits.substring(6, 8), radix: 16) : 0xFF;
  return (alpha << 24) | rgb;
}

/// Formats ARGB as `#RRGGBB`, or `#RRGGBBAA` when the colour is translucent.
String formatAppThemeHexColor(int argb) {
  final alpha = (argb >> 24) & 0xFF;
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  if (alpha == 0xFF) return '#${rgb.toUpperCase()}';
  final a = alpha.toRadixString(16).padLeft(2, '0').toUpperCase();
  return '#${rgb.toUpperCase()}$a';
}

/// The six base shadow atoms for one brightness, all lengths in px.
///
/// [color] is ARGB; `ShadowScale.derive` multiplies its alpha by [opacity], so
/// a colour that already carries alpha (tweakcn stores
/// `hsl(330 70% 30% / 0.12)`) stays correct instead of being overwritten.
class AppThemeShadowAtoms {
  const AppThemeShadowAtoms({
    required this.color,
    required this.opacity,
    required this.blur,
    required this.spread,
    required this.offsetX,
    required this.offsetY,
  });

  /// Reads a `shadowAtoms` schema object.
  factory AppThemeShadowAtoms.fromJson(Object? value) {
    final map = appThemeStringKeyed(value, 'shadow atoms');
    return AppThemeShadowAtoms(
      color: parseAppThemeHexColor(appThemeString(map, 'color')),
      opacity: appThemeNum(map, 'opacity'),
      blur: appThemeNum(map, 'blur'),
      spread: appThemeNum(map, 'spread'),
      offsetX: appThemeNum(map, 'offsetX'),
      offsetY: appThemeNum(map, 'offsetY'),
    );
  }

  /// ARGB shadow colour.
  final int color;

  /// Base alpha in 0..1.
  final double opacity;

  /// Blur radius in px.
  final double blur;

  /// Spread radius in px.
  final double spread;

  /// Horizontal offset in px.
  final double offsetX;

  /// Vertical offset in px.
  final double offsetY;
}

/// One preset, normalised: ARGB colours, rem/em numbers, base shadow atoms.
///
/// `radius` and `spacing` stay in rem and `tracking` in em; the generator
/// converts them to logical pixels (`* 16`) because that is the unit Flutter's
/// `letterSpacing` and `SpacingScale` use. Radius is already unitless.
class AppThemeValues {
  AppThemeValues({
    required this.id,
    required this.name,
    required this.light,
    required this.dark,
    required this.radius,
    required this.spacing,
    required this.tracking,
    required this.lightShadow,
    required this.darkShadow,
    required this.fonts,
  });

  /// Reads a decoded preset document.
  factory AppThemeValues.fromJson(Map<String, Object?> preset) {
    final light = appThemeStringKeyed(preset['light'], 'light');
    final dark = appThemeStringKeyed(preset['dark'], 'dark');
    final shadow = appThemeStringKeyed(preset['shadow'], 'shadow');
    final trackingMap = appThemeStringKeyed(preset['tracking'], 'tracking');
    final fontsMap = preset['fonts'] == null
        ? const <String, Object?>{}
        : appThemeStringKeyed(preset['fonts'], 'fonts');
    return AppThemeValues(
      id: appThemeString(preset, 'id'),
      name: appThemeString(preset, 'name'),
      light: _appThemeColors(light, 'light'),
      dark: _appThemeColors(dark, 'dark'),
      radius: appThemeNum(preset, 'radius'),
      spacing: appThemeNum(preset, 'spacing'),
      tracking: <String, double>{
        for (final step in const ['normal', 'tight', 'wide'])
          if (trackingMap.containsKey(step))
            step: appThemeNum(trackingMap, step),
      },
      lightShadow: AppThemeShadowAtoms.fromJson(shadow['light']),
      darkShadow: AppThemeShadowAtoms.fromJson(shadow['dark']),
      fonts: <String, String>{
        for (final slot in const ['sans', 'serif', 'mono'])
          if (fontsMap.containsKey(slot)) slot: appThemeString(fontsMap, slot),
      },
    );
  }

  /// Preset id, e.g. `amber-minimal`.
  final String id;

  /// Human readable preset name.
  final String name;

  /// Colour tokens per mode as ARGB.
  final Map<String, int> light, dark;

  /// `radius` in rem (used unitless) and `spacing` in rem.
  final double radius, spacing;

  /// `tracking` in em, keyed `normal`, `tight`, `wide`.
  final Map<String, double> tracking;

  /// Base shadow atoms per mode.
  final AppThemeShadowAtoms lightShadow, darkShadow;

  /// Font family lists keyed `sans`, `serif`, `mono`; may be empty.
  final Map<String, String> fonts;

  /// Dart identifier fragment for [id], e.g. `amberMinimal`.
  String get prefix => camelCaseAppThemeId(id);

  /// Capitalised [prefix], e.g. `AmberMinimal`.
  String get classPrefix =>
      prefix.isEmpty ? prefix : prefix[0].toUpperCase() + prefix.substring(1);

  /// Whether the preset names at least one family.
  bool get hasFonts => fonts.isNotEmpty;
}

/// `amber-minimal` -> `amberMinimal`; also strips anything that cannot appear
/// in a Dart identifier so the emitted names always compile.
String camelCaseAppThemeId(String id) {
  final parts = id.split(RegExp('[^A-Za-z0-9]')).where((p) => p.isNotEmpty);
  final buffer = StringBuffer();
  for (final part in parts) {
    if (buffer.isEmpty) {
      buffer.write(part.toLowerCase());
    } else {
      buffer.write(capitalizeAppThemeId(part));
    }
  }
  return buffer.toString();
}

/// Sibling library of [uri]: same directory, [name] file name.
String siblingAppThemeUri(String uri, String name) {
  final cut = uri.lastIndexOf('/');
  return cut < 0 ? name : '${uri.substring(0, cut + 1)}$name';
}

/// Upper-cases the first character of [text].
String capitalizeAppThemeId(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// [value] as a `String`-keyed map, or a [FormatException].
Map<String, Object?> appThemeStringKeyed(Object? value, String what) {
  if (value is! Map) throw FormatException('$what is not an object: $value');
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

/// [map[key]] as a string, or a [FormatException] naming the missing key.
String appThemeString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) throw FormatException('$key is not a string: $value');
  return value;
}

/// [map[key]] as a double, or a [FormatException] naming the missing key.
double appThemeNum(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! num) throw FormatException('$key is not a number: $value');
  return value.toDouble();
}

Map<String, int> _appThemeColors(Map<String, Object?> map, String mode) {
  final colors = <String, int>{};
  for (final key in appThemeColorTokenKeys) {
    colors[key] = parseAppThemeHexColor(appThemeString(map, key));
  }
  final extra = map.keys.toSet().difference(appThemeColorTokenKeys.toSet());
  if (extra.isNotEmpty) {
    throw FormatException('$mode has unknown tokens: ${extra.join(', ')}');
  }
  return colors;
}
