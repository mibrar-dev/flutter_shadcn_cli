import 'package:flutter_shadcn_cli/src/application/services/theme/app_theme_generator.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/app_theme_values.dart';
import 'package:test/test.dart';

import '../support/theme_preset_fixture.dart';

void main() {
  group('colour parsing', () {
    test('#RRGGBB defaults to opaque', () {
      expect(parseAppThemeHexColor('#FFFFFF'), 0xFFFFFFFF);
      expect(parseAppThemeHexColor('#000000'), 0xFF000000);
    });

    test('#RRGGBBAA keeps the alpha byte', () {
      expect(parseAppThemeHexColor('#FFFFFF1A'), 0x1AFFFFFF);
      expect(parseAppThemeHexColor('#00000000'), 0x00000000);
    });

    test('rejects anything that is not a hex colour', () {
      for (final value in <String>[
        'FFFFFF',
        '#FFF',
        '0xFFFFFF',
        '#FFFFFF1',
        'rgb(0,0,0)',
        '',
      ]) {
        expect(
          () => parseAppThemeHexColor(value),
          throwsA(isA<FormatException>()),
          reason: value,
        );
      }
    });

    test('round-trips through formatAppThemeHexColor', () {
      for (final value in <String>[
        '#FFFFFF',
        '#000000',
        '#FFFFFF1A',
        '#3B82F6'
      ]) {
        expect(formatAppThemeHexColor(parseAppThemeHexColor(value)), value);
      }
    });

    test('upper-cases and pads on format', () {
      expect(formatAppThemeHexColor(0xFFabcdef), '#ABCDEF');
      expect(formatAppThemeHexColor(0x0A000001), '#0000010A');
    });
  });

  group('AppThemeValues.fromJson', () {
    test('reads colours, numbers, tracking, shadows and fonts', () {
      final values =
          AppThemeValues.fromJson(themePresetJson(id: 'amber-minimal'));
      expect(values.id, 'amber-minimal');
      expect(values.name, 'Fixture Preset');
      expect(values.prefix, 'amberMinimal');
      expect(values.classPrefix, 'AmberMinimal');
      expect(values.hasFonts, isTrue);
      expect(values.fonts.keys, <String>['sans', 'mono']);
      expect(values.light.length, appThemeColorTokenKeys.length);
      expect(values.light['border'], 0xFFE0E0E0);
      expect(values.radius, 0.5);
      expect(values.spacing, 0.25);
      expect(values.tracking, <String, double>{'normal': 0});
      expect(values.lightShadow.offsetY, 1);
      expect(values.darkShadow.opacity, closeTo(0.1, 1e-9));
    });

    test('a preset without fonts is still complete', () {
      final values = AppThemeValues.fromJson(
        themePresetJson(includeFonts: false),
      );
      expect(values.hasFonts, isFalse);
      expect(values.fonts, isEmpty);
    });

    test('tracking is required, matching themes.schema.json', () {
      expect(
        () => AppThemeValues.fromJson(themePresetJson(includeTracking: false)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('tracking is not an object'),
          ),
        ),
      );
    });

    test('rejects an unknown colour token instead of dropping it', () {
      final preset = themePresetJson();
      (preset['light'] as Map<String, dynamic>)['brand'] = '#123456';
      expect(
        () => AppThemeValues.fromJson(preset),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('light has unknown tokens: brand'),
          ),
        ),
      );
    });

    test('rejects a missing colour token', () {
      final preset = themePresetJson();
      (preset['dark'] as Map<String, dynamic>).remove('ring');
      expect(
        () => AppThemeValues.fromJson(preset),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('ring is not a string'),
          ),
        ),
      );
    });

    test('rejects non-numeric radius and a missing id', () {
      final preset = themePresetJson()..['radius'] = '0.5';
      expect(
        () => AppThemeValues.fromJson(preset),
        throwsA(isA<FormatException>()),
      );
      final withoutId = themePresetJson()..remove('id');
      expect(
        () => AppThemeValues.fromJson(withoutId),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('id is not a string'),
          ),
        ),
      );
    });
  });

  group('identifier helpers', () {
    test('camelCaseAppThemeId produces a Dart-safe fragment', () {
      expect(camelCaseAppThemeId('amber-minimal'), 'amberMinimal');
      expect(camelCaseAppThemeId('vercel'), 'vercel');
      expect(camelCaseAppThemeId('t3-chat'), 't3Chat');
      expect(camelCaseAppThemeId('odd id_here'), 'oddIdHere');
      expect(camelCaseAppThemeId('---'), '');
      expect(camelCaseAppThemeId('42'), '42');
    });

    test('capitalizeAppThemeId only touches the first character', () {
      expect(capitalizeAppThemeId('light'), 'Light');
      expect(capitalizeAppThemeId(''), '');
      expect(capitalizeAppThemeId('aBc'), 'ABc');
    });

    test('siblingAppThemeUri rewrites the file name in place', () {
      expect(siblingAppThemeUri('theme.dart', 'tokens.dart'), 'tokens.dart');
      expect(
        siblingAppThemeUri(
          'package:flutter_shadcn_kit/registry/theme/theme.dart',
          'tokens.dart',
        ),
        'package:flutter_shadcn_kit/registry/theme/tokens.dart',
      );
    });
  });

  group('renderAppTheme', () {
    test('emits the values-only blocks in the documented order', () {
      final source = renderAppTheme(AppThemeValues.fromJson(themePresetJson()));
      final order = <String>[
        'const ShadcnColors fixturePresetLightColors',
        'const ShadcnColors fixturePresetDarkColors',
        'final ShadcnTokens fixturePresetLightTokens',
        'final ShadcnTokens fixturePresetDarkTokens',
        'const ShadcnFonts fixturePresetFonts',
        'ShadcnThemeData buildFixturePresetTheme',
      ];
      var cursor = -1;
      for (final marker in order) {
        final at = source.indexOf(marker);
        expect(at, greaterThan(cursor), reason: marker);
        cursor = at;
      }
      expect(
        source,
        startsWith(
          '// Generated by flutter_shadcn — regenerate with: '
          'flutter_shadcn theme apply fixture-preset --refresh',
        ),
      );
      // Two import groups separated by one blank line (tall style).
      expect(
        source,
        contains(
          "import 'package:flutter/widgets.dart';\n\n"
          "import 'theme.dart';\n"
          "import 'color_tokens.dart';\n"
          "import 'tokens.dart';",
        ),
      );
      expect(source, endsWith('}\n'));
    });

    test('appThemeFileHeader substitutes the preset id once', () {
      expect(
        appThemeFileHeader('vercel'),
        '// Generated by flutter_shadcn — regenerate with: '
        'flutter_shadcn theme apply vercel --refresh',
      );
      expect(appThemeFileHeaderTemplate, contains('@id'));
      expect(appThemeFileHeader('a'), isNot(contains('@id')));
    });

    test('converts rem to logical pixels but leaves radius unitless', () {
      final source = renderAppTheme(AppThemeValues.fromJson(themePresetJson()));
      expect(source, contains('radius: 0.5,'));
      expect(source, contains('spacingBase: 4.0,'));
      expect(source, contains('trackingNormal: 0.0,'));
      expect(source, contains('opacity: 0.1,'));
    });

    test('omits the fonts block when the preset names no family', () {
      final source = renderAppTheme(
        AppThemeValues.fromJson(themePresetJson(includeFonts: false)),
      );
      expect(source, isNot(contains('ShadcnFonts')));
      expect(source, isNot(contains('fonts:')));
    });

    test('keeps a one-line call when it fits in 80 columns', () {
      final source = renderAppTheme(
        AppThemeValues.fromJson(
          themePresetJson()
            ..['radius'] = 0
            ..['spacing'] = 0.125
            ..['tracking'] = <String, dynamic>{'normal': 0},
        ),
      );
      expect(source, contains('radius: 0.0,\n  spacingBase: 2.0,'));
    });

    test('escapes quotes and backslashes in font families', () {
      final source = renderAppTheme(
        AppThemeValues.fromJson(
          themePresetJson()
            ..['fonts'] = <String, dynamic>{'sans': "it's \\ fine"},
        ),
      );
      expect(source, contains(r"fontSans: 'it\'s \\ fine'"));
    });
  });
}
