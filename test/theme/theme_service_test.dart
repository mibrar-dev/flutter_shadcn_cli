import 'dart:convert';

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

    test('refuses a manifest that is not schemaVersion 2', () {
      final source = ThemeRegistrySource.overReader(
        (_) async => jsonEncode(<String, dynamic>{'schemaVersion': 1}),
      );
      expect(
        source.loadManifest(),
        throwsA(
          isA<ThemeApplyException>().having(
            (error) => error.message,
            'message',
            contains('has schemaVersion 1; this CLI needs the v2 manifest'),
          ),
        ),
      );
    });

    test('reports every malformed themes entry at once', () {
      final source = ThemeRegistrySource.overReader(
        (_) async => jsonEncode(<String, dynamic>{
          'schemaVersion': 2,
          'themes': <String, dynamic>{
            'broken': <String, dynamic>{'name': ''},
            'nope': 'string',
          },
        }),
      );
      expect(
        source.loadManifest(),
        throwsA(
          isA<ThemeApplyException>()
              .having((error) => error.message, 'message',
                  contains('has no usable `themes` section'))
              .having(
                (error) => error.details,
                'details',
                containsAll(<String>[
                  'themes.broken.file is required.',
                  'themes.broken.name is required.',
                  'themes.broken.modes must be a non-empty array.',
                  'themes.nope must be an object.',
                ]),
              ),
        ),
      );
    });

    // The generated kit manifest has primitive cycles (plan 9.7) and no
    // fileHashes entry for themes/*.json, so the theme flow must not depend on
    // whole-manifest validation; `validate` / `doctor` own that.
    test('tolerates a manifest the full v2 validator rejects', () async {
      final source = ThemeRegistrySource.overReader(
        (relPath) async => relPath == ThemeRegistrySource.manifestPath
            ? jsonEncode(<String, dynamic>{
                'schemaVersion': 2,
                'themes': <String, dynamic>{
                  'only': <String, dynamic>{
                    'file': 'themes/only.json',
                    'name': 'Only',
                    'modes': <String>['light'],
                  },
                },
              })
            : null,
        describe: (rel) => rel,
      );
      expect((await source.loadManifest()).themes.keys, <String>['only']);
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
