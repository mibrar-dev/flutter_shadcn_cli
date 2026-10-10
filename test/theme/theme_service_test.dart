import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/theme/theme_models.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_registry_source.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:test/test.dart';

import 'theme_test_harness.dart';

void main() {
  late ThemeTestHarness harness;
  late RegistryManifest manifest;

  setUpAll(() async {
    manifest = await fixtureSource().loadManifest();
  });

  // A fresh project per test: apply() records state in shadcn.lock and in the
  // project config, so the cases must not share a root.
  setUp(() {
    harness = ThemeTestHarness.create('theme_service_')..useManifest(manifest);
  });

  group('registry source', () {
    test('loads the fixture manifest', () {
      expect(harness.manifest.themes.keys, <String>['claude', 'vercel']);
      expect(harness.manifest.themes['vercel']!.file, 'themes/vercel.json');
      expect(
          harness.manifest.themes['vercel']!.modes, <String>['light', 'dark']);
      expect(harness.manifest.install.root, 'lib/ui/shadcn');
    });

    test('reports a missing manifest', () {
      final source = ThemeRegistrySource.overReader((_) async => null);
      expect(
        source.loadManifest(),
        throwsA(
          isA<ThemeApplyException>().having(
            (error) => error.message,
            'message',
            contains('Registry file not found: manifests/registry.json'),
          ),
        ),
      );
    });

    // The theme flow runs the full ManifestSchemaValidator, so the message
    // names the file and the version rule and every validator error lands in
    // `details`. Derived from the valid fixture so only the mutated rule fires.
    test('refuses a manifest that is not schemaVersion 2', () {
      final source = _sourceOver({
        ThemeRegistrySource.manifestPath: jsonEncode(
          _validManifest()..['schemaVersion'] = 1,
        ),
      });
      expect(
        source.loadManifest(),
        throwsA(
          isA<ThemeApplyException>()
              .having(
                (error) => error.message,
                'message',
                allOf(
                  contains(ThemeRegistrySource.manifestPath),
                  contains('is not a valid registry manifest'),
                  contains('schemaVersion 2'),
                ),
              )
              .having(
                (error) => error.details.join('\n'),
                'details',
                contains('schemaVersion must be 2 (got 1)'),
              ),
        ),
      );
    });

    // Whole-manifest validation owns the wording, so this asserts the
    // contract (one error per malformed entry, all reported at once) without
    // pinning another batch's phrasing.
    test('reports every malformed themes entry at once', () {
      final source = _sourceOver({
        ThemeRegistrySource.manifestPath: jsonEncode(_validManifest()),
      });
      final decoded = _validManifest();
      decoded['themes'] = <String, dynamic>{
        'broken': <String, dynamic>{'name': ''},
        'nope': 'string',
      };
      final malformed = _sourceOver({
        ThemeRegistrySource.manifestPath: jsonEncode(decoded),
      });
      expect(source.loadManifest(), completes);
      expect(
        malformed.loadManifest(),
        throwsA(
          isA<ThemeApplyException>()
              .having((error) => error.message, 'message',
                  contains('is not a valid registry manifest'))
              .having(
                (error) => error.details.join('\n'),
                'details',
                allOf(
                  contains('themes.broken'),
                  contains('themes.nope'),
                  // Nothing else is wrong with this manifest.
                  isNot(contains('missing required top-level key')),
                ),
              ),
        ),
      );
    });

    // Whole-manifest validation really runs: a missing digest for a declared
    // layer file is refused. (`themes/*.json` are deliberately exempt — they
    // are consumed to render app_theme.dart, never copied — even though the
    // kit now publishes their digests for diffing.)
    test('refuses a manifest whose fileHashes miss a declared layer file', () {
      final decoded = _validManifest();
      (decoded['fileHashes']! as Map<String, dynamic>)
          .remove('foundation/data.dart');
      final source = _sourceOver({
        ThemeRegistrySource.manifestPath: jsonEncode(decoded),
      });
      expect(
        source.loadManifest(),
        throwsA(
          isA<ThemeApplyException>()
              .having((error) => error.message, 'message',
                  contains('is not a valid registry manifest'))
              .having(
                (error) => error.details.join('\n'),
                'details',
                contains(
                    'fileHashes: missing entry for "foundation/data.dart"'),
              ),
        ),
      );
    });

    test('requires a configured registry', () {
      expect(
        ThemeRegistrySourceResolver.fromConfig(const ShadcnConfig()),
        isNull,
      );
      expect(
        () => ThemeRegistrySourceResolver.requireFromConfig(
          const ShadcnConfig(),
        ),
        throwsA(
          isA<ThemeApplyException>().having(
            (error) => error.message,
            'message',
            contains('No shadcn registry is configured'),
          ),
        ),
      );
    });

    test('resolves the registry from the config and its overrides', () {
      final byPath = ThemeRegistrySourceResolver.fromConfig(
        const ShadcnConfig(registryPath: '/tmp/registry'),
      )!;
      expect(byPath.describe('themes/vercel.json'),
          contains(p.join('/tmp/registry', 'themes/vercel.json')));

      final byUrl = ThemeRegistrySourceResolver.fromConfig(
        const ShadcnConfig(registryUrl: 'https://example.com/lib/registry'),
      )!;
      expect(
          byUrl.describe('manifests/registry.json'), contains('example.com'));

      final override = ThemeRegistrySourceResolver.fromConfig(
        const ShadcnConfig(registryPath: '/tmp/registry'),
        registryUrlOverride: 'https://example.com/override',
      )!;
      expect(override.describe('manifests/registry.json'),
          contains('example.com/override'));
    });
  });

  group('listPresets', () {
    test('is sorted by id and marks the locked preset as current', () async {
      final presets = await harness.service().listPresets();
      expect(presets.map((entry) => entry.id), <String>['claude', 'vercel']);
      expect(presets.any((entry) => entry.isCurrent), isFalse);
      expect(presets.first.name, 'Claude');
      expect(presets.first.supportsDark, isTrue);

      await harness.service().apply('vercel');
      final after = await harness.service().listPresets();
      expect(
        after.where((entry) => entry.isCurrent).map((entry) => entry.id),
        <String>['vercel'],
      );
    });

    test('findPreset accepts an id or a display name', () {
      expect(harness.service().findPreset('Vercel')!.id, 'vercel');
      expect(harness.service().findPreset('  CLAUDE ')!.id, 'claude');
      expect(harness.service().findPreset('nope'), isNull);
      expect(harness.service().findPreset('   '), isNull);
    });
  });
}

/// The fixture manifest as a fresh mutable map, so one test can break exactly
/// one rule and assert that rule in isolation.
Map<String, dynamic> _validManifest() =>
    jsonDecode(File(p.join(fixtureRegistryRoot, 'manifests/registry.json'))
        .readAsStringSync()) as Map<String, dynamic>;

/// A [ThemeRegistrySource] serving the given registry-relative documents.
ThemeRegistrySource _sourceOver(Map<String, String> documents) {
  return ThemeRegistrySource.overReader(
    (relPath) async => documents[relPath],
    describe: (rel) => rel,
  );
}
