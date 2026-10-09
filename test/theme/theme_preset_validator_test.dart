import 'package:flutter_shadcn_cli/src/application/services/theme/theme_preset_validator.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_schema_validator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/kit_registry.dart';
import '../support/theme_preset_fixture.dart';

void main() {
  List<String> errorsFor(Map<String, dynamic> preset) =>
      ThemePresetValidator.validate(preset, label: 'themes/x.json').errors;

  test('a complete preset validates', () {
    final result = ThemePresetValidator.validate(
      themePresetJson(id: 'amber-minimal', name: 'Amber Minimal'),
    );
    expect(result.isValid, isTrue, reason: result.errors.join('\n'));
    expect(result.errors, isEmpty);
  });

  test('fonts and shadowsDerived are optional but typed when present', () {
    final minimal = themePresetJson(includeFonts: false)
      ..remove('shadowsDerived');
    expect(errorsFor(minimal), isEmpty);
    expect(errorsFor(themePresetJson()..['shadowsDerived'] = 'nope'),
        contains(contains('"shadowsDerived" must be one of cli, from-legacy')));
  });

  group('top level', () {
    test('reports every missing required key at once', () {
      final errors = errorsFor(<String, dynamic>{});
      for (final key in <String>[
        'id',
        'name',
        'schemaVersion',
        'light',
        'dark',
        'radius',
        'spacing',
        'tracking',
        'shadow',
      ]) {
        expect(errors, contains(contains('missing required key "$key"')));
      }
    });

    test('rejects unknown keys', () {
      expect(
        errorsFor(themePresetJson()..['preset_themes'] = true),
        contains('themes/x.json: unknown key "preset_themes".'),
      );
    });

    test('rejects a wrong schemaVersion and a bad id', () {
      expect(
        errorsFor(themePresetJson()..['schemaVersion'] = 1),
        contains(contains('"schemaVersion" must be 2')),
      );
      expect(
        errorsFor(themePresetJson(id: 'Amber_Minimal')),
        contains(contains('"id" must match')),
      );
    });

    test('rejects an empty name', () {
      expect(
          errorsFor(themePresetJson(name: '')), contains(contains('"name"')));
    });
  });

  group('colour maps', () {
    test('require all 32 tokens in both modes', () {
      for (final mode in <String>['light', 'dark']) {
        final preset = themePresetJson();
        (preset[mode]! as Map<String, dynamic>).remove('chart5');
        expect(errorsFor(preset),
            contains('themes/x.json: "$mode.chart5" is required.'));
      }
    });

    test('reject unknown tokens', () {
      final preset = themePresetJson();
      (preset['light']! as Map<String, dynamic>)['brand'] = '#123456';
      expect(errorsFor(preset),
          contains('themes/x.json: "light" has unknown token "brand".'));
    });

    test('require upper case #RRGGBB[AA] values', () {
      for (final value in <String>['#ffffff', '#FFF', 'FFFFFF', '#FFFFFF1']) {
        final preset = themePresetJson();
        (preset['dark']! as Map<String, dynamic>)['ring'] = value;
        expect(
          errorsFor(preset),
          contains(contains(
              '"dark.ring" must be #RRGGBB or #RRGGBBAA in upper case')),
          reason: value,
        );
      }
    });

    test('reject a colour map that is not an object', () {
      expect(errorsFor(themePresetJson()..['light'] = 'nope'),
          contains(contains('"light" must be an object')));
    });
  });

  group('numbers', () {
    test('radius may be 0 but not negative', () {
      expect(errorsFor(themePresetJson()..['radius'] = 0), isEmpty);
      expect(errorsFor(themePresetJson()..['radius'] = -1),
          contains('themes/x.json: "radius" must be >= 0 (got -1).'));
      expect(errorsFor(themePresetJson()..['radius'] = '0.5'),
          contains(contains('"radius" must be a number')));
    });

    test('spacing must be strictly positive', () {
      expect(errorsFor(themePresetJson()..['spacing'] = 0),
          contains('themes/x.json: "spacing" must be > 0 (got 0).'));
    });
  });

  group('tracking', () {
    test('requires the normal step and allows tight/wide', () {
      expect(errorsFor(themePresetJson()), isEmpty);
      final extended = themePresetJson()
        ..['tracking'] = <String, dynamic>{
          'normal': 0,
          'tight': -0.025,
          'wide': 0.05,
        };
      expect(errorsFor(extended), isEmpty);
      expect(
        errorsFor(
            themePresetJson()..['tracking'] = <String, dynamic>{'tight': 1}),
        contains('themes/x.json: "tracking.normal" is required.'),
      );
    });

    test('rejects unknown steps and non-numbers', () {
      final preset = themePresetJson()
        ..['tracking'] = <String, dynamic>{'normal': 0, 'loose': 1};
      expect(errorsFor(preset),
          contains('themes/x.json: "tracking" has unknown step "loose".'));
      expect(
        errorsFor(
            themePresetJson()..['tracking'] = <String, dynamic>{'normal': 'x'}),
        contains('themes/x.json: "tracking.normal" must be a number (got x).'),
      );
    });
  });

  group('shadow', () {
    test('requires both modes with the six atoms', () {
      final preset = themePresetJson();
      (preset['shadow']! as Map<String, dynamic>).remove('dark');
      expect(errorsFor(preset),
          contains(contains('"shadow.dark" must be an object')));

      final partial = themePresetJson();
      ((partial['shadow']! as Map<String, dynamic>)['light']!
              as Map<String, dynamic>)
          .remove('offsetY');
      expect(errorsFor(partial),
          contains('themes/x.json: "shadow.light.offsetY" is required.'));
    });

    test('bounds opacity and blur', () {
      final tooOpaque = themePresetJson();
      ((tooOpaque['shadow']! as Map<String, dynamic>)['light']!
          as Map<String, dynamic>)['opacity'] = 1.5;
      expect(
          errorsFor(tooOpaque),
          contains(
              'themes/x.json: "shadow.light.opacity" must be within 0..1.'));

      final negativeBlur = themePresetJson();
      ((negativeBlur['shadow']! as Map<String, dynamic>)['dark']!
          as Map<String, dynamic>)['blur'] = -1;
      expect(errorsFor(negativeBlur),
          contains('themes/x.json: "shadow.dark.blur" must be >= 0.'));
    });

    test('rejects unknown modes and atoms, and a bad colour', () {
      final unknownMode = themePresetJson();
      (unknownMode['shadow']! as Map<String, dynamic>)['sepia'] =
          <String, dynamic>{};
      expect(errorsFor(unknownMode),
          contains('themes/x.json: "shadow" has unknown mode "sepia".'));

      final unknownAtom = themePresetJson();
      ((unknownAtom['shadow']! as Map<String, dynamic>)['light']!
          as Map<String, dynamic>)['blur2'] = 1;
      expect(errorsFor(unknownAtom),
          contains('themes/x.json: "shadow.light" has unknown atom "blur2".'));

      final badColour = themePresetJson();
      ((badColour['shadow']! as Map<String, dynamic>)['light']!
          as Map<String, dynamic>)['color'] = 'black';
      expect(
          errorsFor(badColour),
          contains(
              contains('"shadow.light.color" must be #RRGGBB or #RRGGBBAA')));
    });
  });

  group('fonts', () {
    test('rejects an empty block, unknown slots and empty strings', () {
      expect(errorsFor(themePresetJson()..['fonts'] = <String, dynamic>{}),
          contains('themes/x.json: "fonts" must name at least one family.'));
      expect(
          errorsFor(themePresetJson()
            ..['fonts'] = <String, dynamic>{'display': 'Inter'}),
          contains('themes/x.json: "fonts" has unknown slot "display".'));
      expect(
          errorsFor(
              themePresetJson()..['fonts'] = <String, dynamic>{'sans': ''}),
          contains('themes/x.json: "fonts.sans" must be a non-empty string.'));
    });
  });

  // Every preset the CLI can apply must pass, or `theme apply <id>` would
  // refuse a preset the kit publishes.
  group('the real registry', () {
    final kit = findKitPackageRoot();

    test('every published preset validates and matches its manifest id', () {
      final manifest = kitRegistryManifest(kit!);
      final themes = manifest['themes']! as Map<String, dynamic>;
      expect(themes, isNotEmpty);

      for (final id in themes.keys) {
        final entry = themes[id]! as Map<String, dynamic>;
        final preset = kitPresetJson(kit, id);
        final result = ThemePresetValidator.validate(
          preset,
          label: entry['file'] as String,
        );
        expect(result.isValid, isTrue, reason: result.errors.join('\n'));
        expect(preset['id'], id);
        expect(preset['name'], entry['name']);
      }
    }, skip: kit == null ? 'shadcn_flutter_kit not present' : null);

    // Tripwire for the two documented gaps in `ManifestSchemaValidator`
    // (batch B1) that the generated kit manifest trips over: primitive
    // dependency cycles (plan 9.7 made them legal) and `themes/*.json` entries
    // without a `fileHashes` digest. When B1 lands the fix this test flips to
    // a clean `isValid`; any OTHER error fails here too.
    test('the kit manifest only trips the two known validator gaps', () {
      final result = ManifestSchemaValidator.validate(
        kitRegistryManifest(kit!),
        registryRoot: p.join(kit, 'lib', 'registry'),
      );
      if (result.isValid) return;
      final knownGap = result.errors.every(
        (error) =>
            error.contains('dependency cycle detected') ||
            error.startsWith('fileHashes: missing entry for "themes/'),
      );
      expect(
        knownGap,
        isTrue,
        reason: 'unexpected manifest errors:\n${result.errors.join('\n')}',
      );
    }, skip: kit == null ? 'shadcn_flutter_kit not present' : null);
  });
}
