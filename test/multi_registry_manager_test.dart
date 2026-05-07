import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/multi_registry_manager.dart';
import 'package:flutter_shadcn_cli/src/registry_directory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('MultiRegistryManager', () {
    late Directory tempRoot;
    late Directory appRoot;
    late Directory registryBaseA;
    late Directory registryBaseB;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('shadcn_multi_mgr_');
      appRoot = Directory(p.join(tempRoot.path, 'app'))..createSync();
      registryBaseA = Directory(p.join(tempRoot.path, 'reg_a'))..createSync();
      registryBaseB = Directory(p.join(tempRoot.path, 'reg_b'))..createSync();
      _writeSimpleRegistry(registryBaseA, marker: 'A');
      _writeSimpleRegistry(registryBaseB, marker: 'B');
      File(p.join(appRoot.path, 'pubspec.yaml')).writeAsStringSync(
        [
          'name: test_app',
          'dependencies:',
          '  flutter:',
          '    sdk: flutter',
        ].join('\n'),
      );
      await ShadcnConfig.save(
        appRoot.path,
        ShadcnConfig(
          defaultNamespace: 'shadcn',
          includeMeta: true,
          registries: {
            'shadcn': RegistryConfigEntry(
              registryMode: 'local',
              registryPath: p.join(registryBaseA.path, 'registry'),
              installPath: 'lib/ui/shadcn',
              sharedPath: 'lib/ui/shadcn/shared',
              enabled: true,
            ),
            'alt': RegistryConfigEntry(
              registryMode: 'local',
              registryPath: p.join(registryBaseB.path, 'registry'),
              installPath: 'lib/ui/alt',
              sharedPath: 'lib/ui/alt/shared',
              enabled: true,
            ),
          },
        ),
      );
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('unqualified add fails when component is ambiguous', () async {
      final current = await ShadcnConfig.load(appRoot.path);
      await ShadcnConfig.save(
        appRoot.path,
        current.copyWith(defaultNamespace: 'unknown'),
      );
      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
      );
      await expectLater(
        () => manager.runAdd(['button']),
        throwsA(isA<MultiRegistryException>()),
      );
    });

    test('unqualified add fails when default and another registry both match',
        () async {
      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
      );
      await expectLater(
        () => manager.runAdd(['button']),
        throwsA(
          isA<MultiRegistryException>().having(
            (error) => error.message,
            'message',
            contains('ambiguous across registries'),
          ),
        ),
      );
    });

    test('unqualified add uses default registry when it is the only match',
        () async {
      final current = await ShadcnConfig.load(appRoot.path);
      await ShadcnConfig.save(
        appRoot.path,
        current.withRegistry(
          'alt',
          current.registryConfig('alt')!.copyWith(enabled: false),
        ),
      );
      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
      );
      await manager.runAdd(['button']);
      expect(
        File(
          p.join(
            appRoot.path,
            'lib',
            'ui',
            'shadcn',
            'components',
            'button',
            'button.dart',
          ),
        ).existsSync(),
        isTrue,
      );
    });

    test('qualified @namespace/component installs from selected registry',
        () async {
      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
      );
      await manager.runAdd(['@alt/button']);
      expect(
        File(
          p.join(
            appRoot.path,
            'lib',
            'ui',
            'alt',
            'components',
            'button',
            'button.dart',
          ),
        ).existsSync(),
        isTrue,
      );
    });

    test('same component id from two registries keeps separate manifests',
        () async {
      final registriesPath = _writeRegistriesFile(tempRoot, [
        _localRegistryEntry(
          namespace: 'shadcn',
          baseUrl: 'https://example.com/shadcn/',
        ),
        _localRegistryEntry(
          namespace: 'alt',
          baseUrl: 'https://example.com/alt/',
        ),
      ]);
      final current = await ShadcnConfig.load(appRoot.path);
      await ShadcnConfig.save(
        appRoot.path,
        current.copyWith(registriesPath: registriesPath),
      );
      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
        directoryPath: registriesPath,
      );

      await manager.runAdd(['@shadcn/button', '@alt/button']);

      final shadcnManifest = File(
        p.join(appRoot.path, '.shadcn', 'components', 'shadcn', 'button.json'),
      );
      final altManifest = File(
        p.join(appRoot.path, '.shadcn', 'components', 'alt', 'button.json'),
      );
      expect(shadcnManifest.existsSync(), isTrue);
      expect(altManifest.existsSync(), isTrue);

      final shadcn =
          jsonDecode(shadcnManifest.readAsStringSync()) as Map<String, dynamic>;
      final alt =
          jsonDecode(altManifest.readAsStringSync()) as Map<String, dynamic>;
      expect(shadcn['namespace'], 'shadcn');
      expect(shadcn['componentId'], 'button');
      expect(shadcn['qualifiedId'], '@shadcn/button');
      expect(alt['namespace'], 'alt');
      expect(alt['componentId'], 'button');
      expect(alt['qualifiedId'], '@alt/button');
      expect(
        File(p.join(appRoot.path, '.shadcn', 'components', 'button.json'))
            .existsSync(),
        isFalse,
      );
    });

    test('qualified namespace:component installs from selected registry',
        () async {
      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
      );
      await manager.runAdd(['alt:button']);
      expect(
        File(
          p.join(
            appRoot.path,
            'lib',
            'ui',
            'alt',
            'components',
            'button',
            'button.dart',
          ),
        ).existsSync(),
        isTrue,
      );
    });

    test('configureDefaultRegistryLocal persists local registry settings',
        () async {
      final registriesPath = _writeRegistriesFile(tempRoot, [
        _inlineRegistryEntry(
          baseUrl: 'https://example.com/remote/',
          actions: const [
            {
              'type': 'ensureDirs',
              'dirs': ['lib/ui/shadcn'],
            },
          ],
        ),
      ]);

      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
      );

      final next = await manager.configureDefaultRegistryLocal(
        'shadcn',
        registriesPath: registriesPath,
        registryPath: p.join(registryBaseA.path, 'registry'),
      );

      expect(next.effectiveDefaultNamespace, 'shadcn');
      expect(next.registriesPath, registriesPath);
      expect(next.registryMode, 'local');
      expect(next.registryPath, p.join(registryBaseA.path, 'registry'));

      final persisted = await ShadcnConfig.load(appRoot.path);
      final entry = persisted.registryConfig('shadcn');
      expect(persisted.registriesPath, registriesPath);
      expect(entry?.registryMode, 'local');
      expect(entry?.registryPath, p.join(registryBaseA.path, 'registry'));
      expect(entry?.installPath, 'lib/ui/shadcn');
      expect(entry?.sharedPath, 'lib/ui/shadcn/shared');
    });

    test('registry path override is used as current-engine source', () async {
      final overrideBase = Directory(p.join(tempRoot.path, 'reg_override'))
        ..createSync();
      _writeSimpleRegistry(overrideBase, marker: 'Override');

      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
        registryPathOverride: p.join(overrideBase.path, 'registry'),
      );
      await manager.runAdd(['@shadcn/button']);

      final installed = File(
        p.join(
          appRoot.path,
          'lib',
          'ui',
          'shadcn',
          'components',
          'button',
          'button.dart',
        ),
      );
      expect(installed.readAsStringSync(), contains('ButtonOverride'));
    });

    test('invalid components schema blocks public add', () async {
      final invalidBase = Directory(p.join(tempRoot.path, 'invalid_schema'))
        ..createSync();
      _writeSimpleRegistry(invalidBase, marker: 'InvalidSchema');
      File(p.join(invalidBase.path, 'registry', 'components.schema.json'))
          .writeAsStringSync(_schemaRequiringBlockedField());
      final current = await ShadcnConfig.load(appRoot.path);
      await ShadcnConfig.save(
        appRoot.path,
        current
            .withRegistry(
              'shadcn',
              RegistryConfigEntry(
                registryMode: 'local',
                registryPath: p.join(invalidBase.path, 'registry'),
                componentsSchemaPath: 'components.schema.json',
                installPath: 'lib/ui/shadcn',
                sharedPath: 'lib/ui/shadcn/shared',
                enabled: true,
              ),
            )
            .withRegistry(
              'alt',
              current.registryConfig('alt')!.copyWith(enabled: false),
            ),
      );
      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
      );

      await expectLater(
        () => manager.runAdd(['button']),
        throwsA(anything),
      );
    });

    test('skip integrity bypasses invalid components schema for developer add',
        () async {
      final invalidBase =
          Directory(p.join(tempRoot.path, 'invalid_schema_bypass'))
            ..createSync();
      _writeSimpleRegistry(invalidBase, marker: 'SchemaBypass');
      File(p.join(invalidBase.path, 'registry', 'components.schema.json'))
          .writeAsStringSync(_schemaRequiringBlockedField());
      final current = await ShadcnConfig.load(appRoot.path);
      await ShadcnConfig.save(
        appRoot.path,
        current
            .withRegistry(
              'shadcn',
              RegistryConfigEntry(
                registryMode: 'local',
                registryPath: p.join(invalidBase.path, 'registry'),
                componentsSchemaPath: 'components.schema.json',
                installPath: 'lib/ui/shadcn',
                sharedPath: 'lib/ui/shadcn/shared',
                enabled: true,
              ),
            )
            .withRegistry(
              'alt',
              current.registryConfig('alt')!.copyWith(enabled: false),
            ),
      );
      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        skipIntegrity: true,
        logger: CliLogger(),
      );

      await manager.runAdd(['button']);

      final installed = File(
        p.join(
          appRoot.path,
          'lib',
          'ui',
          'shadcn',
          'components',
          'button',
          'button.dart',
        ),
      );
      expect(installed.readAsStringSync(), contains('ButtonSchemaBypass'));
    });

    test('component add rejects symlink escape through install path', () async {
      final outside = Directory(p.join(tempRoot.path, 'outside'))..createSync();
      Directory(p.join(appRoot.path, 'lib')).createSync();
      Link(p.join(appRoot.path, 'lib', 'ui')).createSync(outside.path);
      final current = await ShadcnConfig.load(appRoot.path);
      await ShadcnConfig.save(
        appRoot.path,
        current.withRegistry(
          'alt',
          current.registryConfig('alt')!.copyWith(enabled: false),
        ),
      );
      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
      );

      await expectLater(
        () => manager.runAdd(['button']),
        throwsA(anything),
      );
      expect(
        File(
          p.join(outside.path, 'shadcn/components/button/button.dart'),
        ).existsSync(),
        isFalse,
      );
    });

    test('registry path override is used for inline init copyFiles', () async {
      final overrideBase = Directory(p.join(tempRoot.path, 'inline_override'))
        ..createSync();
      Directory(p.join(overrideBase.path, 'registry', 'shared'))
          .createSync(recursive: true);
      _writeEmptyRegistryManifest(
          Directory(p.join(overrideBase.path, 'registry')));
      File(p.join(overrideBase.path, 'registry', 'shared', 'token.dart'))
          .writeAsStringSync('class LocalOverrideToken {}');

      final registriesPath = _writeRegistriesFile(tempRoot, [
        _inlineRegistryEntry(
          baseUrl: 'https://example.com/remote/',
          actions: [
            {
              'type': 'copyFiles',
              'base': 'registry',
              'destBase': 'lib/ui/shadcn',
              'files': ['registry/shared/token.dart'],
            }
          ],
        ),
      ]);

      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
        directoryPath: registriesPath,
        registryPathOverride: p.join(overrideBase.path, 'registry'),
      );

      await manager.runNamespaceInit('shadcn', assumeYes: true);

      final installed = File(
        p.join(appRoot.path, 'lib', 'ui', 'shadcn', 'shared', 'token.dart'),
      );
      expect(installed.readAsStringSync(), contains('LocalOverrideToken'));
    });

    test('offline inline init requires components manifest validation',
        () async {
      await ShadcnConfig.save(appRoot.path, const ShadcnConfig());
      final registriesPath = _writeRegistriesFile(tempRoot, [
        _inlineRegistryEntry(
          baseUrl: 'https://example.com/remote/',
          actions: [
            {
              'type': 'ensureDirs',
              'dirs': ['lib/ui/shadcn/offline_init'],
            }
          ],
        ),
      ]);

      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
        directoryPath: registriesPath,
      );

      await expectLater(
        () => manager.runNamespaceInit('shadcn', assumeYes: true),
        throwsA(anything),
      );
    });

    test(
        'skip integrity allows offline inline init without components manifest',
        () async {
      await ShadcnConfig.save(appRoot.path, const ShadcnConfig());
      final registriesPath = _writeRegistriesFile(tempRoot, [
        _inlineRegistryEntry(
          baseUrl: 'https://example.com/remote/',
          actions: [
            {
              'type': 'ensureDirs',
              'dirs': ['lib/ui/shadcn/offline_init'],
            }
          ],
        ),
      ]);

      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        skipIntegrity: true,
        logger: CliLogger(),
        directoryPath: registriesPath,
      );

      await manager.runNamespaceInit('shadcn', assumeYes: true);

      final generated = Directory(
        p.join(appRoot.path, 'lib', 'ui', 'shadcn', 'offline_init'),
      );
      expect(generated.existsSync(), isTrue);
    });

    test('registry path override is used for inline assets copyFiles',
        () async {
      final overrideBase = Directory(p.join(tempRoot.path, 'asset_override'))
        ..createSync();
      Directory(p.join(overrideBase.path, 'registry', 'shared', 'fonts'))
          .createSync(recursive: true);
      File(
        p.join(
          overrideBase.path,
          'registry',
          'shared',
          'fonts',
          'typography_fonts.dart',
        ),
      ).writeAsStringSync('class LocalAssetOverride {}');

      final registriesPath = _writeRegistriesFile(tempRoot, [
        _inlineRegistryEntry(
          baseUrl: 'https://example.com/remote/',
          actions: [
            {
              'type': 'copyFiles',
              'base': 'registry',
              'destBase': 'lib/ui/shadcn',
              'files': ['registry/shared/fonts/typography_fonts.dart'],
            }
          ],
        ),
      ]);

      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
        directoryPath: registriesPath,
        registryPathOverride: p.join(overrideBase.path, 'registry'),
      );

      final applied = await manager.runInlineAssets(
        namespace: 'shadcn',
        installIcons: false,
        installTypography: true,
        installAll: false,
      );

      expect(applied, isTrue);
      final installed = File(
        p.join(
          appRoot.path,
          'lib',
          'ui',
          'shadcn',
          'shared',
          'fonts',
          'typography_fonts.dart',
        ),
      );
      expect(installed.readAsStringSync(), contains('LocalAssetOverride'));
    });

    test('registry path override preserves directory components path',
        () async {
      final overrideBase = Directory(p.join(tempRoot.path, 'custom_path'))
        ..createSync();
      final registryRoot = Directory(p.join(overrideBase.path, 'registry'))
        ..createSync(recursive: true);
      Directory(p.join(registryRoot.path, 'manifests'))
          .createSync(recursive: true);
      Directory(p.join(registryRoot.path, 'components', 'button'))
          .createSync(recursive: true);
      File(p.join(registryRoot.path, 'components', 'button', 'button.dart'))
          .writeAsStringSync('class ButtonCustomPath {}');
      File(p.join(registryRoot.path, 'components.schema.json'))
          .writeAsStringSync(_allowAnySchemaJson());
      File(p.join(registryRoot.path, 'manifests', 'components.schema.json'))
          .writeAsStringSync(_allowAnySchemaJson());
      File(p.join(registryRoot.path, 'manifests', 'components.json'))
          .writeAsStringSync(_componentsJson(marker: 'CustomPath'));

      final registriesPath = _writeRegistriesFile(tempRoot, [
        _inlineRegistryEntry(
          baseUrl: 'https://example.com/remote/',
          paths: {
            'componentsJson': 'registry/manifests/components.json',
            'componentsSchemaJson': 'registry/manifests/components.schema.json',
          },
          actions: const [],
        ),
      ]);

      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
        directoryPath: registriesPath,
        registryPathOverride: registryRoot.path,
      );

      await manager.runAdd(['@shadcn/button']);

      final installed = File(
        p.join(
          appRoot.path,
          'lib',
          'ui',
          'shadcn',
          'components',
          'button',
          'button.dart',
        ),
      );
      expect(installed.readAsStringSync(), contains('ButtonCustomPath'));
    });

    test(
        'registry path override uses explicit schema path for component manifest',
        () async {
      final overrideBase = Directory(p.join(tempRoot.path, 'explicit_schema'))
        ..createSync();
      final registryRoot = Directory(p.join(overrideBase.path, 'registry'))
        ..createSync(recursive: true);
      Directory(p.join(registryRoot.path, 'components', 'button'))
          .createSync(recursive: true);
      File(p.join(registryRoot.path, 'components', 'button', 'button.dart'))
          .writeAsStringSync('class ButtonExplicitSchema {}');
      File(p.join(registryRoot.path, 'components.schema.json'))
          .writeAsStringSync(_allowAnySchemaJson());
      File(p.join(registryRoot.path, 'components.json'))
          .writeAsStringSync(_componentsJson(marker: 'ExplicitSchema'));

      final registriesPath = _writeRegistriesFile(tempRoot, [
        _inlineRegistryEntry(
          baseUrl: 'https://example.com/remote/',
          paths: {
            'componentsJson': 'components.json',
            'componentsSchemaJson': 'components.schema.json',
          },
          actions: const [],
        ),
      ]);

      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
        directoryPath: registriesPath,
        registryPathOverride: registryRoot.path,
      );

      await manager.runAdd(['@shadcn/button']);

      final installed = File(
        p.join(
          appRoot.path,
          'lib',
          'ui',
          'shadcn',
          'components',
          'button',
          'button.dart',
        ),
      );
      expect(installed.readAsStringSync(), contains('ButtonExplicitSchema'));
    });

    test('relative registry path override is used for inline init copyFiles',
        () async {
      final overrideRoot = Directory(p.join(appRoot.path, 'local_registry'))
        ..createSync();
      Directory(p.join(overrideRoot.path, 'registry', 'shared'))
          .createSync(recursive: true);
      _writeEmptyRegistryManifest(
          Directory(p.join(overrideRoot.path, 'registry')));
      File(p.join(overrideRoot.path, 'registry', 'shared', 'relative.dart'))
          .writeAsStringSync('class RelativeOverrideToken {}');

      final registriesPath = _writeRegistriesFile(tempRoot, [
        _inlineRegistryEntry(
          baseUrl: 'https://example.com/remote/',
          actions: [
            {
              'type': 'copyFiles',
              'base': 'registry',
              'destBase': 'lib/ui/shadcn',
              'files': ['registry/shared/relative.dart'],
            }
          ],
        ),
      ]);

      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
        directoryPath: registriesPath,
        registryPathOverride: p.join('local_registry', 'registry'),
      );

      await manager.runNamespaceInit('shadcn', assumeYes: true);

      final installed = File(
        p.join(appRoot.path, 'lib', 'ui', 'shadcn', 'shared', 'relative.dart'),
      );
      expect(installed.readAsStringSync(), contains('RelativeOverrideToken'));
    });

    test('failed inline assets do not mutate config', () async {
      final registriesPath = _writeRegistriesFile(tempRoot, [
        _inlineRegistryEntry(
          baseUrl: 'https://example.com/remote/',
          actions: [
            {
              'type': 'message',
              'lines': ['no asset actions here'],
            }
          ],
        ),
      ]);
      final before = File(p.join(appRoot.path, '.shadcn', 'config.json'))
          .readAsStringSync();

      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
        directoryPath: registriesPath,
      );
      final applied = await manager.runInlineAssets(
        namespace: 'shadcn',
        installIcons: false,
        installTypography: true,
        installAll: false,
      );

      expect(applied, isFalse);
      final after = File(p.join(appRoot.path, '.shadcn', 'config.json'))
          .readAsStringSync();
      expect(after, before);
    });

    test('failed inline asset execution does not mutate config', () async {
      final registriesPath = _writeRegistriesFile(tempRoot, [
        _inlineRegistryEntry(
          baseUrl: 'https://example.com/remote/',
          actions: [
            {
              'type': 'copyFiles',
              'base': 'registry',
              'destBase': 'lib/ui/shadcn',
              'files': ['registry/shared/fonts/missing.dart'],
            }
          ],
        ),
      ]);
      final before = File(p.join(appRoot.path, '.shadcn', 'config.json'))
          .readAsStringSync();

      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
        directoryPath: registriesPath,
        registryPathOverride: p.join(registryBaseA.path, 'registry'),
      );

      await expectLater(
        () => manager.runInlineAssets(
          namespace: 'shadcn',
          installIcons: false,
          installTypography: true,
          installAll: false,
        ),
        throwsA(anything),
      );

      final after = File(p.join(appRoot.path, '.shadcn', 'config.json'))
          .readAsStringSync();
      expect(after, before);
    });

    test('setDefaultRegistry updates config and list reflects default',
        () async {
      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
      );
      final updated = await manager.setDefaultRegistry('alt');
      expect(updated.effectiveDefaultNamespace, 'alt');

      final listed = await manager.listRegistries();
      final alt = listed.firstWhere((entry) => entry.namespace == 'alt');
      expect(alt.isDefault, isTrue);
    });

    test(
        'setDefaultRegistry keeps theme manifests but omits legacy converter wiring',
        () async {
      final registriesPath = _writeRegistriesFile(tempRoot, [
        _inlineRegistryEntry(
          baseUrl: 'https://example.com/registry/',
          paths: {
            'componentsJson': 'components.json',
            'themesJson': 'registry/manifests/theme.index.json',
            'themesSchemaJson': 'registry/manifests/themes.index.schema.json',
          },
          actions: const [
            {
              'type': 'ensureDirs',
              'dirs': ['assets/official'],
            },
          ],
        )..['install'] = {
            'namespace': 'official',
            'root': 'lib/ui/official',
          },
      ]);
      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
        directoryPath: registriesPath,
      );

      final updated = await manager.setDefaultRegistry('official');
      final entry = updated.registryConfig('official');

      expect(updated.effectiveDefaultNamespace, 'official');
      expect(entry, isNotNull);
      expect(entry!.themesPath, 'registry/manifests/theme.index.json');
      expect(
        entry.themesSchemaPath,
        'registry/manifests/themes.index.schema.json',
      );
      expect(entry.themeConverterDartPath, isNull);
      expect(entry.toJson().containsKey('themeConverterDartPath'), isFalse);
    });

    test('inline assets install and rollback use registry actions', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      server.listen((request) async {
        final path = request.uri.path;
        if (path == '/registries.json') {
          request.response.write(
            jsonEncode({
              'schemaVersion': 1,
              'registries': [
                {
                  'id': 'shadcn_entry',
                  'displayName': 'Shadcn',
                  'maintainers': ['team'],
                  'repo': 'https://example.com/repo',
                  'license': 'MIT',
                  'minCliVersion': '0.1.0',
                  'baseUrl': 'https://example.com/registry/',
                  'paths': {'componentsJson': 'components.json'},
                  'install': {'namespace': 'shadcn', 'root': 'lib/ui/shadcn'},
                  'init': {
                    'version': 1,
                    'actions': [
                      {
                        'type': 'ensureDirs',
                        'dirs': ['assets/fonts']
                      },
                      {
                        'type': 'copyFiles',
                        'base': 'registry',
                        'destBase': 'lib/ui/shadcn',
                        'files': ['registry/shared/fonts/typography_fonts.dart']
                      },
                      {
                        'type': 'mergePubspec',
                        'dependencies': {'google_fonts': '^6.2.1'},
                        'flutterAssets': ['assets/fonts/GeistSans-Regular.ttf'],
                        'flutterFonts': [
                          {
                            'family': 'GeistSans',
                            'fonts': [
                              {
                                'asset': 'assets/fonts/GeistSans-Regular.ttf',
                                'weight': 400
                              }
                            ]
                          }
                        ]
                      },
                      {
                        'type': 'ensureDirs',
                        'dirs': ['assets/icons']
                      },
                    ]
                  }
                }
              ]
            }),
          );
          await request.response.close();
          return;
        }
        if (path == '/registry/shared/fonts/typography_fonts.dart') {
          request.response.write('class TypographyFonts {}');
          await request.response.close();
          return;
        }
        if (path == '/components.json') {
          request.response.write(
            jsonEncode({
              'schemaVersion': 1,
              'name': 'inline_assets',
              'flutter': {'minSdk': '3.0.0'},
              'defaults': {
                'installPath': 'lib/ui/shadcn',
                'sharedPath': 'lib/ui/shadcn/shared',
              },
              'shared': [],
              'components': [],
            }),
          );
          await request.response.close();
          return;
        }
        request.response.statusCode = 404;
        await request.response.close();
      });

      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: false,
        logger: CliLogger(verbose: true),
        directoryUrl:
            'http://${server.address.host}:${server.port}/registries.json',
      );
      final loadedDirectory = await RegistryDirectoryClient().load(
        projectRoot: appRoot.path,
        directoryUrl:
            'http://${server.address.host}:${server.port}/registries.json',
        offline: false,
        currentCliVersion: '0.1.8',
      );
      expect(
          loadedDirectory.registries
              .any((entry) => entry.namespace == 'shadcn'),
          isTrue);
      await ShadcnConfig.save(
        appRoot.path,
        ShadcnConfig(
          defaultNamespace: 'shadcn',
          registries: {
            'shadcn': RegistryConfigEntry(
              registryMode: 'remote',
              registryUrl: 'http://${server.address.host}:${server.port}/',
              baseUrl: 'http://${server.address.host}:${server.port}/',
              installPath: 'lib/ui/shadcn',
              sharedPath: 'lib/ui/shadcn/shared',
              enabled: true,
            ),
            'alt': RegistryConfigEntry(
              registryMode: 'local',
              registryPath: p.join(registryBaseB.path, 'registry'),
              installPath: 'lib/ui/alt',
              sharedPath: 'lib/ui/alt/shared',
              enabled: true,
            ),
          },
        ),
      );
      final applied = await manager.runInlineAssets(
        namespace: 'shadcn',
        installIcons: false,
        installTypography: true,
        installAll: false,
      );
      expect(applied, isTrue);
      expect(
        File(
          p.join(
            appRoot.path,
            'lib',
            'ui',
            'shadcn',
            'shared',
            'fonts',
            'typography_fonts.dart',
          ),
        ).existsSync(),
        isTrue,
      );
      final pubspecBeforeRollback =
          File(p.join(appRoot.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspecBeforeRollback.contains('google_fonts: ^6.2.1'), isTrue);
      expect(pubspecBeforeRollback.contains('family: GeistSans'), isTrue);

      final rolledBack = await manager.rollbackInlineAssets(
        namespace: 'shadcn',
        removeIcons: false,
        removeTypography: true,
        removeAll: false,
      );
      expect(rolledBack, isTrue);
      expect(
        File(
          p.join(
            appRoot.path,
            'lib',
            'ui',
            'shadcn',
            'shared',
            'fonts',
            'typography_fonts.dart',
          ),
        ).existsSync(),
        isFalse,
      );
      final pubspecAfterRollback =
          File(p.join(appRoot.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspecAfterRollback.contains('google_fonts: ^6.2.1'), isFalse);
      expect(pubspecAfterRollback.contains('family: GeistSans'), isFalse);
    });
  });
}

void _writeSimpleRegistry(Directory baseDir, {required String marker}) {
  final registryRoot = Directory(p.join(baseDir.path, 'registry'))
    ..createSync(recursive: true);
  final componentDir = Directory(
    p.join(baseDir.path, 'registry', 'components', 'button'),
  )..createSync(recursive: true);
  File(p.join(componentDir.path, 'button.dart'))
      .writeAsStringSync('class Button$marker {}');
  File(p.join(registryRoot.path, 'components.schema.json'))
      .writeAsStringSync(_allowAnySchemaJson());
  File(p.join(registryRoot.path, 'components.json')).writeAsStringSync(
    _componentsJson(marker: marker),
  );
}

void _writeEmptyRegistryManifest(Directory registryRoot) {
  registryRoot.createSync(recursive: true);
  File(p.join(registryRoot.path, 'components.schema.json'))
      .writeAsStringSync(_allowAnySchemaJson());
  File(p.join(registryRoot.path, 'components.json')).writeAsStringSync(
    jsonEncode({
      'schemaVersion': 1,
      'name': 'inline_registry',
      'defaults': {
        'installPath': 'lib/ui/shadcn',
        'sharedPath': 'lib/ui/shadcn/shared',
      },
      'components': [],
    }),
  );
}

String _allowAnySchemaJson() {
  return jsonEncode({
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  });
}

String _componentsJson({required String marker}) {
  return jsonEncode({
    'schemaVersion': 1,
    'name': 'registry_$marker',
    'flutter': {'minSdk': '3.0.0'},
    'defaults': {
      'installPath': 'lib/ui/$marker',
      'sharedPath': 'lib/ui/$marker/shared',
    },
    'shared': [],
    'components': [
      {
        'id': 'button',
        'name': 'Button',
        'description': 'button',
        'category': 'core',
        'files': [
          {
            'source': 'registry/components/button/button.dart',
            'destination': 'components/button/button.dart',
          }
        ],
        'shared': [],
        'dependsOn': [],
        'pubspec': {
          'dependencies': {},
        },
        'assets': [],
        'postInstall': [],
      }
    ],
  });
}

String _schemaRequiringBlockedField() {
  return jsonEncode({
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    'type': 'object',
    'required': ['blocked'],
    'properties': {
      'blocked': {'type': 'boolean'},
    },
  });
}

String _writeRegistriesFile(
  Directory root,
  List<Map<String, dynamic>> entries,
) {
  final file = File(p.join(root.path, 'registries.json'));
  file.writeAsStringSync(
    jsonEncode({
      'schemaVersion': 1,
      'registries': entries,
    }),
  );
  return file.path;
}

Map<String, dynamic> _inlineRegistryEntry({
  required String baseUrl,
  required List<Map<String, dynamic>> actions,
  Map<String, dynamic>? paths,
}) {
  return {
    'id': 'shadcn_entry',
    'displayName': 'Shadcn',
    'maintainers': ['team'],
    'repo': 'https://example.com/repo',
    'license': 'MIT',
    'minCliVersion': '0.1.0',
    'baseUrl': baseUrl,
    'paths': paths ?? {'componentsJson': 'components.json'},
    'install': {'namespace': 'shadcn', 'root': 'lib/ui/shadcn'},
    'init': {
      'version': 1,
      'actions': actions,
    },
  };
}

Map<String, dynamic> _localRegistryEntry({
  required String namespace,
  required String baseUrl,
}) {
  return {
    'id': '${namespace}_entry',
    'displayName': namespace,
    'maintainers': ['team'],
    'repo': 'https://example.com/repo',
    'license': 'MIT',
    'minCliVersion': '0.1.0',
    'baseUrl': baseUrl,
    'paths': {'componentsJson': 'registry/components.json'},
    'install': {'namespace': namespace, 'root': 'lib/ui/$namespace'},
  };
}
