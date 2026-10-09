// Installer entry points (batch B6) against the installer core B4 shipped:
// `applyThemePreset` is the one call `init` / `add` / `update` need.
//
// The registry is resolved the way the CLI resolves it: from the project's
// `.shadcn/config.json`, which `init` writes before the preset step. Callers
// that already hold a `RegistryFileReader` (B4's `Installer` keeps one, but
// privately) pass it as `source:` — see the last test.
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer_file_install_part.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/installer.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'theme_test_harness.dart';

void main() {
  late ThemeTestHarness harness;
  late RegistryManifest manifest;

  setUpAll(() async {
    manifest = await fixtureSource().loadManifest();
  });

  setUp(() async {
    harness = ThemeTestHarness.create('installer_theme_')
      ..useManifest(manifest);
    // What `init` leaves behind before it picks a preset.
    await ShadcnConfig.save(
      harness.projectRoot,
      const ShadcnConfig(
        defaultNamespace: 'shadcn',
        registries: <String, RegistryConfigEntry>{
          'shadcn': RegistryConfigEntry(
            registryMode: 'local',
            registryPath: '../registry',
            installPath: 'lib/ui/shadcn',
            enabled: true,
          ),
        },
      ),
    );
  });

  Installer installer({String installRoot = 'lib/ui/shadcn'}) => Installer(
        manifest: harness.manifest,
        projectRoot: harness.projectRoot,
        reader: DirectoryRegistryFileReader(fixtureRegistryRoot),
        installRoot: installRoot,
        manifestSha256: 'a' * 64,
      );

  /// The registry the project config points at.
  ThemeRegistrySource configuredSource() => ThemeRegistrySource.overReader(
        (relPath) async {
          final file = File(p.join(fixtureRegistryRoot, relPath));
          return file.existsSync() ? file.readAsString() : null;
        },
        registryRoot: fixtureRegistryRoot,
        describe: (rel) => p.join(fixtureRegistryRoot, rel),
      );

  test('applyThemePreset writes app_theme.dart under the install root',
      () async {
    final result = await installer().applyThemePreset(
      'vercel',
      source: configuredSource(),
    );
    expect(result, isNotNull);
    expect(result!.status, ThemeApplyStatus.created);
    expect(result.path, 'lib/ui/shadcn/theme/app_theme.dart');
    expect(harness.themeFile().readAsStringSync(),
        contains('ShadcnThemeData buildVercelTheme'));
    expect(harness.lock().theme!.id, 'vercel');
    expect(harness.lock().theme!.sha256, result.sha256);
  });

  test('a custom install root is honoured end to end', () async {
    final result = await installer(installRoot: 'lib/ui/kit')
        .applyThemePreset('claude', source: configuredSource());
    expect(result!.path, 'lib/ui/kit/theme/app_theme.dart');
    expect(harness.themeFile('lib/ui/kit').existsSync(), isTrue);
    expect(harness.lock().installRoot, 'lib/ui/kit');
  });

  test('listThemePresets reads the manifest themes map', () async {
    final presets =
        await installer().listThemePresets(source: configuredSource());
    expect(presets.map((entry) => entry.id), <String>['claude', 'vercel']);
  });

  test('an empty preset id is a no-op', () async {
    expect(await installer().applyThemePreset('  '), isNull);
  });

  test('no configured registry at all degrades to a warning', () async {
    // The state `init` starts from: nothing in .shadcn/config.json yet, so
    // there is nothing to resolve a preset against. `init` must still install
    // the core and let `theme apply` finish the job later.
    await ShadcnConfig.save(harness.projectRoot, const ShadcnConfig());
    expect(await installer().applyThemePreset('vercel'), isNull);
    expect(harness.themeFile().existsSync(), isFalse);
  });

  test('a configured but unreachable registry fails loudly', () async {
    // The config points at a directory that does not exist. Silently skipping
    // the theme would hide a real misconfiguration, so the read error is
    // surfaced as a ThemeApplyException instead of a raw transport exception.
    expect(
      installer().applyThemePreset('vercel'),
      throwsA(
        isA<ThemeApplyException>().having(
          (error) => error.message,
          'message',
          contains('Cannot read'),
        ),
      ),
    );
  });

  test('a drifted app_theme.dart is reported, not overwritten', () async {
    final app = installer();
    await app.applyThemePreset('vercel', source: configuredSource());
    harness.themeFile().writeAsStringSync('// hand edited\n');

    final refused =
        await app.applyThemePreset('claude', source: configuredSource());
    expect(refused!.status, ThemeApplyStatus.drift);
    expect(refused.drift!.kind, ThemeDriftKind.modified);
    expect(harness.themeFile().readAsStringSync(), '// hand edited\n');
  });

  test('an unknown preset propagates ThemeApplyException', () async {
    expect(
      installer().applyThemePreset('nope', source: configuredSource()),
      throwsA(
        isA<ThemeApplyException>().having(
          (error) => error.message,
          'message',
          contains('Unknown theme preset "nope"'),
        ),
      ),
    );
  });

  test('the picker feeds applyThemePreset', () async {
    final app = installer();
    final presets = await app.listThemePresets(source: configuredSource());
    expect(presets, isNotEmpty);

    // The picker itself is covered in theme_preset_prompt_test.dart; here we
    // only prove the installer exposes the catalogue it feeds.
    final chosen = presets.firstWhere((entry) => entry.id == 'claude');
    final result =
        await app.applyThemePreset(chosen.id, source: configuredSource());
    expect(result!.presetId, 'claude');
  });
}
