import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:flutter_shadcn_cli/src/config.dart';

void main() {
  test('config roundtrip preserves settings', () async {
    final tempDir = Directory.systemTemp.createTempSync('shadcn_config_test_');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    const config = ShadcnConfig(
      classPrefix: 'App',
      themeId: 'modern-minimal',
      registryMode: 'local',
      registryPath: '/tmp/registry',
      registryUrl: 'https://example.com',
      installPath: 'lib/ui/shadcn',
      sharedPath: 'lib/ui/shadcn/shared',
      includeReadme: false,
      includeMeta: true,
      includePreview: false,
      includeFiles: ['meta'],
      excludeFiles: ['preview'],
      pathAliases: {
        'ui': 'lib/ui',
        'hooks': 'lib/hooks',
      },
    );

    await ShadcnConfig.save(tempDir.path, config);

    final file = File(p.join(tempDir.path, '.shadcn', 'config.json'));
    expect(file.existsSync(), isTrue);

    final loaded = await ShadcnConfig.load(tempDir.path);
    expect(loaded.classPrefix, config.classPrefix);
    expect(loaded.themeId, config.themeId);
    expect(loaded.registryMode, config.registryMode);
    expect(loaded.registryPath, config.registryPath);
    expect(loaded.registryUrl, config.registryUrl);
    expect(loaded.installPath, config.installPath);
    expect(loaded.sharedPath, config.sharedPath);
    expect(loaded.includeReadme, config.includeReadme);
    expect(loaded.includeMeta, config.includeMeta);
    expect(loaded.includePreview, config.includePreview);
    expect(loaded.includeFiles, config.includeFiles);
    expect(loaded.excludeFiles, config.excludeFiles);
    expect(loaded.pathAliases, config.pathAliases);
  });

  test('active registry include/exclude file settings are surfaced', () async {
    final tempDir = Directory.systemTemp.createTempSync('shadcn_config_test_');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    const config = ShadcnConfig(
      defaultNamespace: 'orient_ui',
      registries: {
        'shadcn': RegistryConfigEntry(
          includeFiles: ['meta'],
          enabled: true,
        ),
        'orient_ui': RegistryConfigEntry(
          includeFiles: ['preview'],
          excludeFiles: ['meta'],
          enabled: true,
        ),
      },
    );

    await ShadcnConfig.save(tempDir.path, config);
    final loaded = await ShadcnConfig.load(tempDir.path);

    expect(loaded.effectiveDefaultNamespace, 'orient_ui');
    expect(loaded.includeFiles, ['preview']);
    expect(loaded.excludeFiles, ['meta']);
    expect(
      loaded.registryConfig('orient_ui')?.includeFiles,
      ['preview'],
    );
  });

  test('config copyWith can clear nullable routing and alias fields', () {
    const config = ShadcnConfig(
      registryPath: '/tmp/registry',
      registryUrl: 'https://example.com/registry',
      includeFiles: ['meta'],
      excludeFiles: ['preview'],
      pathAliases: {'ui': 'lib/ui'},
    );

    final cleared = config.copyWith(
      registryPath: null,
      registryUrl: null,
      includeFiles: null,
      excludeFiles: null,
      pathAliases: null,
    );

    expect(cleared.registryPath, isNull);
    expect(cleared.registryUrl, isNull);
    expect(cleared.includeFiles, isNull);
    expect(cleared.excludeFiles, isNull);
    expect(cleared.pathAliases, isNull);
  });

  test('registry entry copyWith can clear nullable source and file filters',
      () {
    const entry = RegistryConfigEntry(
      registryPath: '/tmp/registry',
      registryUrl: 'https://example.com/registry',
      baseUrl: 'https://example.com/base',
      includeFiles: ['meta'],
      excludeFiles: ['preview'],
    );

    final cleared = entry.copyWith(
      registryPath: null,
      registryUrl: null,
      baseUrl: null,
      includeFiles: null,
      excludeFiles: null,
    );

    expect(cleared.registryPath, isNull);
    expect(cleared.registryUrl, isNull);
    expect(cleared.baseUrl, isNull);
    expect(cleared.includeFiles, isNull);
    expect(cleared.excludeFiles, isNull);
  });

  test('registry entry ignores legacy theme converter path during json mapping',
      () {
    final entry = RegistryConfigEntry.fromJson({
      'themesPath': 'registry/manifests/theme.index.json',
      'themesSchemaPath': 'registry/manifests/themes.index.schema.json',
      'themeConverterDartPath': 'registry/manifests/theme_converter.dart',
    });

    expect(entry.themesPath, 'registry/manifests/theme.index.json');
    expect(
      entry.themesSchemaPath,
      'registry/manifests/themes.index.schema.json',
    );
    expect(entry.themeConverterDartPath, isNull);
    expect(entry.toJson().containsKey('themeConverterDartPath'), isFalse);

    final copied = entry.copyWith(
      themeConverterDartPath: 'registry/ignored.dart',
    );
    expect(copied.themeConverterDartPath, isNull);
    expect(copied.toJson().containsKey('themeConverterDartPath'), isFalse);
  });
}
