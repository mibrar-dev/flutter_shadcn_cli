import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/theme/app_theme_generator.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/app_theme_values.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_models.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_registry_source.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_service.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:test/test.dart';

import '../support/kit_registry.dart';
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
    harness = ThemeTestHarness.create('theme_apply_')..useManifest(manifest);
  });

  test('writes the file and records the selection in the lock', () async {
    final result = await harness.service().apply('vercel');
    expect(result.status, ThemeApplyStatus.created);
    expect(result.presetId, 'vercel');
    expect(result.presetName, 'Vercel');
    expect(result.path, 'lib/ui/shadcn/theme/app_theme.dart');
    expect(result.sourceFile, 'themes/vercel.json');
    expect(result.isClean, isTrue);
    expect(harness.themeFile().readAsStringSync(),
        contains('ShadcnThemeData buildVercelTheme'));

    final lock = harness.lock();
    expect(lock.theme!.id, 'vercel');
    expect(lock.theme!.path, 'lib/ui/shadcn/theme/app_theme.dart');
    expect(lock.theme!.sha256, result.sha256);
    expect(lock.installRoot, 'lib/ui/shadcn');
  });

  test('is idempotent and rewrites nothing', () async {
    await harness.service().apply('vercel');
    final before = harness.themeFile().lastModifiedSync();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final again = await harness.service().apply('vercel');
    expect(again.status, ThemeApplyStatus.unchanged);
    expect(harness.themeFile().lastModifiedSync(), before);
    expect(again.sha256, harness.lock().theme!.sha256);
  });

  test('switches presets without --refresh when the file is CLI-owned',
      () async {
    await harness.service().apply('vercel');
    final switched = await harness.service().apply('claude');
    expect(switched.status, ThemeApplyStatus.refreshed);
    expect(harness.themeFile().readAsStringSync(),
        contains('ShadcnThemeData buildClaudeTheme'));
    expect(harness.lock().theme!.id, 'claude');
    expect(harness.lock().theme!.sha256, switched.sha256);
  });

  test('refuses to overwrite a locally modified file', () async {
    final applied = await harness.service().apply('vercel');
    final file = harness.themeFile()..writeAsStringSync('// hand edited\n');

    final refused = await harness.service().apply('claude');
    expect(refused.status, ThemeApplyStatus.drift);
    expect(refused.isClean, isFalse);
    expect(refused.drift!.kind, ThemeDriftKind.modified);
    expect(refused.drift!.path, 'lib/ui/shadcn/theme/app_theme.dart');
    expect(refused.drift!.recordedSha256, applied.sha256);
    expect(refused.drift!.actualSha256, isNot(applied.sha256));
    expect(file.readAsStringSync(), '// hand edited\n');
    // The lock still describes the bytes on disk.
    expect(harness.lock().theme!.id, 'vercel');
  });

  test('--refresh overwrites the drifted file', () async {
    await harness.service().apply('vercel');
    harness.themeFile().writeAsStringSync('// hand edited\n');

    final refreshed = await harness.service().apply('claude', refresh: true);
    expect(refreshed.status, ThemeApplyStatus.refreshed);
    expect(refreshed.drift!.kind, ThemeDriftKind.modified);
    expect(harness.themeFile().readAsStringSync(),
        contains('ShadcnThemeData buildClaudeTheme'));
    expect(harness.lock().theme!.id, 'claude');
  });

  test('an untracked existing file is drift too, until --refresh', () async {
    harness.themeFile()
      ..createSync(recursive: true)
      ..writeAsStringSync('// hand written\n');

    final refused = await harness.service().apply('vercel');
    expect(refused.status, ThemeApplyStatus.drift);
    expect(refused.drift!.kind, ThemeDriftKind.untracked);
    expect(refused.drift!.recordedSha256, isNull);
    expect(harness.themeFile().readAsStringSync(), '// hand written\n');

    final refreshed = await harness.service().apply('vercel', refresh: true);
    expect(refreshed.status, ThemeApplyStatus.refreshed);
    expect(harness.themeFile().readAsStringSync(),
        contains('ShadcnThemeData buildVercelTheme'));
  });

  test('adopting the exact bytes already on disk records the lock', () async {
    harness.themeFile()
      ..createSync(recursive: true)
      ..writeAsStringSync(
        renderAppTheme(AppThemeValues.fromJson(fixturePresetJson('vercel'))),
      );

    final result = await harness.service().apply('vercel');
    expect(result.status, ThemeApplyStatus.unchanged);
    expect(harness.lock().theme!.sha256, result.sha256);
  });

  test('an unknown preset lists the available ids', () async {
    await expectLater(
      harness.service().apply('nope'),
      throwsA(
        isA<ThemeApplyException>()
            .having((error) => error.message, 'message',
                contains('Unknown theme preset "nope"'))
            .having((error) => error.details.join(), 'details',
                contains('claude, vercel')),
      ),
    );
  });

  test('honours installRootOverride', () async {
    final result =
        await harness.service(installRoot: 'lib/ui/kit').apply('vercel');
    expect(result.path, 'lib/ui/kit/theme/app_theme.dart');
    expect(harness.themeFile('lib/ui/kit').existsSync(), isTrue);
    expect(harness.lock().installRoot, 'lib/ui/kit');
  });

  test('mirrors the preset id into an existing config file', () async {
    await ShadcnConfig.save(harness.projectRoot, const ShadcnConfig());
    await harness.service().apply('vercel');
    expect((await ShadcnConfig.load(harness.projectRoot)).themeId, 'vercel');
  });

  test('does not create a config file when the project has none', () async {
    await harness.service().apply('vercel');
    expect(ShadcnConfig.configFile(harness.projectRoot).existsSync(), isFalse);
  });

  test('rejects a preset whose id contradicts the manifest', () async {
    final renamed = fixturePresetJson('vercel')..['id'] = 'claude';
    expect(
      harness
          .service(
            source: _sourceOf({'themes/vercel.json': renamed}),
          )
          .apply('vercel'),
      throwsA(
        isA<ThemeApplyException>().having(
          (error) => error.message,
          'message',
          allOf(contains('declares id "claude"'),
              contains('the manifest lists it as "vercel"')),
        ),
      ),
    );
  });

  test('rejects a preset that fails themes.schema.json', () async {
    final invalid = fixturePresetJson('vercel');
    (invalid['light']! as Map<String, dynamic>).remove('ring');
    expect(
      harness
          .service(
            source: _sourceOf({'themes/vercel.json': invalid}),
          )
          .apply('vercel'),
      throwsA(
        isA<ThemeApplyException>()
            .having((error) => error.message, 'message',
                contains('themes/vercel.json is invalid'))
            .having((error) => error.details.join(), 'details',
                contains('"light.ring" is required')),
      ),
    );
  });

  test('reports a preset file the registry does not have', () {
    final empty = ThemeRegistrySource.overReader(
      (_) async => null,
      describe: (rel) => rel,
    );
    expect(
      harness.service(source: empty).apply('vercel'),
      throwsA(
        isA<ThemeApplyException>().having(
          (error) => error.message,
          'message',
          contains('themes/vercel.json'),
        ),
      ),
    );
  });

  // End to end against the registry the CLI actually ships against: the 42
  // presets in `flutter_shadcn_kit/lib/registry`.
  group('the real kit registry', () {
    final kit = findKitPackageRoot();

    test('lists the published presets', () async {
      final service = await _kitService(kit, harness);
      final presets = await service.listPresets();
      expect(presets.length, 42);
      expect(presets.map((entry) => entry.id), contains('vercel'));
      expect(
          presets.firstWhere((entry) => entry.id == 'vercel').name, 'Vercel');
    }, skip: kit == null ? 'shadcn_flutter_kit not present' : null);

    test('applies vercel, the init --yes default', () async {
      final service = await _kitService(kit, harness);
      final result = await service.apply('vercel');
      expect(result.status, ThemeApplyStatus.created);
      expect(result.path, 'lib/ui/shadcn/theme/app_theme.dart');
      final generated = harness.themeFile().readAsStringSync();
      expect(generated, contains('const ShadcnColors vercelLightColors'));
      expect(generated, contains('ShadcnThemeData buildVercelTheme'));
      expect(generated, contains("import 'theme.dart';"));
      expect(harness.lock().theme!.id, 'vercel');
      expect(harness.lock().theme!.sha256, result.sha256);
    }, skip: kit == null ? 'shadcn_flutter_kit not present' : null);
  });
}

/// A source serving only the given registry-relative documents.
ThemeRegistrySource _sourceOf(Map<String, Map<String, dynamic>> documents) {
  return ThemeRegistrySource.overReader(
    (relPath) async =>
        documents[relPath] == null ? null : jsonEncode(documents[relPath]),
    describe: (rel) => rel,
  );
}

/// Builds a service over the real kit registry through the CLI's own loader.
Future<ThemeService> _kitService(
  String? kit,
  ThemeTestHarness harness,
) async {
  final root = p.join(kit!, 'lib', 'registry');
  final source = ThemeRegistrySource.overReader(
    (relPath) async {
      final file = File(p.join(root, relPath));
      return file.existsSync() ? file.readAsString() : null;
    },
    registryRoot: root,
    describe: (rel) => p.join(root, rel),
  );
  return ThemeService(
    projectRoot: harness.projectRoot,
    source: source,
    manifest: await source.loadManifest(),
    logger: harness.logger,
  );
}
