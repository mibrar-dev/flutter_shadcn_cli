import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/installer.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:flutter_shadcn_cli/src/state.dart';

void main() {
  group('Installer', () {
    late Directory tempRoot;
    late Directory registryRoot;
    late Directory targetRoot;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('shadcn_cli_test_');
      registryRoot = Directory(p.join(tempRoot.path, 'registry'))..createSync();
      targetRoot = Directory(p.join(tempRoot.path, 'app'))..createSync();
      _writeRegistryFixtures(registryRoot);
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('installs component files with optional filters', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeReadme: false,
          includeMeta: true,
          includePreview: false,
        ),
      );
      _writePubspec(targetRoot);

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        registryBaseUrlOverride: p.dirname(registryRoot.path),
        themesPathOverride: 'registry/manifests/theme.index.json',
      );

      await installer.addComponent('button');

      final installDir = p.join(
        targetRoot.path,
        'lib',
        'ui',
        'shadcn',
        'components',
        'button',
      );

      expect(File(p.join(installDir, 'button.dart')).existsSync(), isTrue);
      expect(File(p.join(installDir, 'meta.json')).existsSync(), isTrue);
      expect(File(p.join(installDir, 'README.md')).existsSync(), isFalse);
      expect(File(p.join(installDir, 'preview.dart')).existsSync(), isFalse);
      expect(
        File(p.join(installDir, 'preview_state.dart')).existsSync(),
        isFalse,
      );
    });

    test('reports component install progress in normal output', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeReadme: false,
          includeMeta: true,
          includePreview: false,
        ),
      );
      _writePubspec(targetRoot);

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );
      final lines = <String>[];
      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(useColor: false, writeLine: lines.add),
        registryBaseUrlOverride: p.dirname(registryRoot.path),
        themesPathOverride: 'registry/manifests/theme.index.json',
      );

      await installer.addComponent('button');

      expect(
        lines,
        containsAllInOrder([
          '... Resolving component: button',
          '• Installing Button (button)',
          '... Installing files for Button (2 files)',
          '... Updating pubspec dependencies for Button',
          '... Writing component manifest for Button',
          '... Regenerating app component aliases',
          '... Syncing component registry manifest',
          '... Updating project state',
        ]),
      );
      expect(
        lines.where((line) => line.contains('Installing file ')),
        isEmpty,
      );
    });

    test('rejects component file destinations outside install scope', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeReadme: false,
          includeMeta: true,
          includePreview: false,
        ),
      );
      _writePubspec(targetRoot);
      File(p.join(p.dirname(registryRoot.path), 'external_button.dart'))
          .writeAsStringSync('class ExternalButton {}');
      _mutateRegistryJson(registryRoot, (json) {
        final components = (json['components'] as List).cast<Map>();
        final button = components.firstWhere((item) => item['id'] == 'button');
        button['files'] = [
          {
            'source': 'external_button.dart',
            'destination': 'lib/escape/button.dart',
          }
        ];
      });

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );
      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        registryNamespace: 'shadcn',
      );

      await expectLater(
        installer.addComponent('button'),
        throwsA(
          predicate(
            (Object error) =>
                error.toString().contains('outside allowed install scope') &&
                error.toString().contains('lib/escape/button.dart'),
          ),
        ),
      );
      expect(
        File(p.join(targetRoot.path, 'lib', 'escape', 'button.dart'))
            .existsSync(),
        isFalse,
      );
    });

    test('rejects component asset paths outside assets root', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeReadme: false,
          includeMeta: true,
          includePreview: false,
        ),
      );
      _writePubspec(targetRoot);
      _mutateRegistryJson(registryRoot, (json) {
        final components = (json['components'] as List).cast<Map>();
        final button = components.firstWhere((item) => item['id'] == 'button');
        button['assets'] = ['lib/secret.txt'];
      });

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );
      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        registryNamespace: 'shadcn',
      );

      await expectLater(
        installer.addComponent('button'),
        throwsA(
          predicate(
            (Object error) =>
                error.toString().contains('Asset path must be under assets/'),
          ),
        ),
      );
      final pubspec =
          File(p.join(targetRoot.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, isNot(contains('lib/secret.txt')));
      expect(
        File(p.join(targetRoot.path, 'lib', 'ui', 'shadcn', 'components',
                'button', 'button.dart'))
            .existsSync(),
        isFalse,
      );
    });

    test('rejects shared file destinations outside shared root', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeReadme: false,
          includeMeta: true,
          includePreview: false,
        ),
      );
      _writePubspec(targetRoot);
      File(p.join(p.dirname(registryRoot.path), 'external_shared.dart'))
          .writeAsStringSync('class ExternalShared {}');
      _mutateRegistryJson(registryRoot, (json) {
        final sharedItems = (json['shared'] as List).cast<Map>();
        final util = sharedItems.firstWhere((item) => item['id'] == 'util');
        util['files'] = [
          {
            'source': 'external_shared.dart',
            'destination': 'pubspec.yaml',
          }
        ];
        final components = (json['components'] as List).cast<Map>();
        final button = components.firstWhere((item) => item['id'] == 'button');
        button['shared'] = ['util'];
      });

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );
      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        registryNamespace: 'shadcn',
      );

      await expectLater(
        installer.addComponent('button'),
        throwsA(
          predicate(
            (Object error) =>
                error
                    .toString()
                    .contains('cannot write reserved project file') &&
                error.toString().contains('pubspec.yaml'),
          ),
        ),
      );
      expect(
        File(p.join(targetRoot.path, 'pubspec.yaml')).readAsStringSync(),
        contains('name: test_app'),
      );
    });

    test('merges component-local JSON locale resources into app ARB', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeReadme: false,
          includeMeta: true,
          includePreview: false,
        ),
      );
      _writePubspec(targetRoot);
      File(p.join(targetRoot.path, 'l10n.yaml')).writeAsStringSync('''
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
''');
      Directory(p.join(targetRoot.path, 'lib', 'l10n'))
          .createSync(recursive: true);
      File(p.join(targetRoot.path, 'lib', 'l10n', 'app_en.arb'))
          .writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          '@@locale': 'en',
          'buttonSave': 'Keep existing',
        }),
      );
      Directory(p.join(
              registryRoot.path, 'components', 'control', 'button', 'locales'))
          .createSync(recursive: true);
      File(p.join(registryRoot.path, 'components', 'control', 'button',
              'locales', 'en.json'))
          .writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'buttonSave': 'Save',
          'buttonCancel': 'Cancel',
          '@buttonCancel': {'description': 'Cancel action label'},
        }),
      );
      _mutateRegistryJson(registryRoot, (json) {
        final components = (json['components'] as List).cast<Map>();
        final button = components.firstWhere((item) => item['id'] == 'button');
        button['locale'] = {
          'defaultLocale': 'en',
          'required': ['en'],
          'resources': [
            {
              'locale': 'en',
              'format': 'json',
              'source': 'registry/components/control/button/locales/en.json',
              'required': true,
            }
          ],
        };
      });

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );
      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
      );

      await installer.addComponent('button');

      final appArb = jsonDecode(
        File(p.join(targetRoot.path, 'lib', 'l10n', 'app_en.arb'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(appArb['buttonSave'], 'Keep existing');
      expect(appArb['buttonCancel'], 'Cancel');
      expect(appArb['@buttonCancel'], {'description': 'Cancel action label'});

      final manifest = jsonDecode(
        File(p.join(targetRoot.path, '.shadcn', 'components', 'button.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final resources =
          ((manifest['locale'] as Map)['resourcesInstalled'] as List)
              .cast<Map<String, dynamic>>();
      expect(resources.single['destination'], 'lib/l10n/app_en.arb');
      expect(resources.single['addedKeys'], contains('buttonCancel'));
      expect(resources.single['addedKeys'], isNot(contains('buttonSave')));

      final lock = await ShadcnLockRepository(targetRoot.path).load();
      final record = lock.componentFor(
        namespace: 'shadcn',
        componentId: 'button',
      );
      expect(record?.localeKeys, [
        'lib/l10n/app_en.arb:@buttonCancel',
        'lib/l10n/app_en.arb:buttonCancel',
      ]);

      await installer.removeComponent('button', force: true);

      final afterRemove = jsonDecode(
        File(p.join(targetRoot.path, 'lib', 'l10n', 'app_en.arb'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(afterRemove['buttonSave'], 'Keep existing');
      expect(afterRemove.containsKey('buttonCancel'), isFalse);
    });

    test('locale install failures expose typed error codes', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeReadme: false,
          includeMeta: true,
          includePreview: false,
        ),
      );
      _writePubspec(targetRoot);

      _mutateRegistryJson(registryRoot, (json) {
        final components = (json['components'] as List).cast<Map>();
        final button = components.firstWhere((item) => item['id'] == 'button');
        button['locale'] = {
          'defaultLocale': 'en',
          'resources': [
            {
              'locale': 'en',
              'format': 'yaml',
              'source': 'registry/components/button/locales/en.yaml',
            }
          ],
        };
      });

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );
      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
      );

      await expectLater(
        installer.addComponent('button'),
        throwsA(
          isA<LocaleInstallException>()
              .having((error) => error.code, 'code', 'missing-l10n-config')
              .having(
                (error) => error.message,
                'message',
                contains('Locale resources require l10n.yaml'),
              ),
        ),
      );

      File(p.join(targetRoot.path, 'l10n.yaml')).writeAsStringSync('''
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
''');

      await expectLater(
        installer.addComponent('button'),
        throwsA(
          isA<LocaleInstallException>()
              .having((error) => error.code, 'code', 'unsupported-format')
              .having(
                (error) => error.message,
                'message',
                contains('Unsupported locale resource format'),
              ),
        ),
      );
    });

    test('registry includeFiles=preview installs preview and preview_state',
        () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          defaultNamespace: 'shadcn',
          registries: {
            'shadcn': RegistryConfigEntry(
              installPath: 'lib/ui/shadcn',
              sharedPath: 'lib/ui/shadcn/shared',
              includeFiles: ['preview'],
              enabled: true,
            ),
          },
        ),
      );
      _writePubspec(targetRoot);

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        registryNamespace: 'shadcn',
      );

      await installer.addComponent('button');

      final installDir = p.join(
        targetRoot.path,
        'lib',
        'ui',
        'shadcn',
        'components',
        'button',
      );

      expect(File(p.join(installDir, 'preview.dart')).existsSync(), isTrue);
      expect(
        File(p.join(installDir, 'preview_state.dart')).existsSync(),
        isTrue,
      );
      expect(File(p.join(installDir, 'meta.json')).existsSync(), isFalse);
      expect(File(p.join(installDir, 'README.md')).existsSync(), isFalse);
    });

    test('registry excludeFiles=preview excludes preview and preview_state',
        () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          defaultNamespace: 'shadcn',
          registries: {
            'shadcn': RegistryConfigEntry(
              installPath: 'lib/ui/shadcn',
              sharedPath: 'lib/ui/shadcn/shared',
              includeMeta: true,
              excludeFiles: ['preview'],
              enabled: true,
            ),
          },
        ),
      );
      _writePubspec(targetRoot);

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        registryNamespace: 'shadcn',
      );

      await installer.addComponent('button');

      final installDir = p.join(
        targetRoot.path,
        'lib',
        'ui',
        'shadcn',
        'components',
        'button',
      );

      expect(File(p.join(installDir, 'meta.json')).existsSync(), isTrue);
      expect(File(p.join(installDir, 'preview.dart')).existsSync(), isFalse);
      expect(
        File(p.join(installDir, 'preview_state.dart')).existsSync(),
        isFalse,
      );
    });

    test('supports @alias paths for install locations', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: '@ui/shadcn',
          sharedPath: '@ui/shadcn/shared',
          includeMeta: true,
          pathAliases: {
            'ui': 'lib/ui',
          },
        ),
      );
      _writePubspec(targetRoot);

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        registryBaseUrlOverride: p.dirname(registryRoot.path),
        themesPathOverride: 'registry/manifests/theme.index.json',
      );

      await installer.addComponent('button');

      final installDir = p.join(
        targetRoot.path,
        'lib',
        'ui',
        'shadcn',
        'components',
        'button',
      );

      expect(File(p.join(installDir, 'button.dart')).existsSync(), isTrue);
    });

    test('adds missing dependencies to pubspec.yaml', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeMeta: true,
        ),
      );
      _writePubspec(targetRoot,
          dependencies: const {'flutter': 'sdk: flutter'});

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        registryBaseUrlOverride: p.dirname(registryRoot.path),
        themesPathOverride: 'registry/manifests/theme.index.json',
      );

      await installer.addComponent('button');

      final pubspec =
          File(p.join(targetRoot.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec.contains('skeletonizer: ^2.1.0+1'), isTrue);

      await installer.addComponent('button');
      final pubspecAgain =
          File(p.join(targetRoot.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspecAgain.contains('skeletonizer: ^2.1.0+1'), isTrue);
    });

    test('writes lockfile record without changing managed dependencies',
        () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          defaultNamespace: 'shadcn',
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeReadme: false,
          includeMeta: true,
          includePreview: false,
        ),
      );
      _writePubspec(targetRoot);

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        registryNamespace: 'shadcn',
      );

      await installer.addComponent('button');

      final lock = await ShadcnLockRepository(targetRoot.path).load();
      expect(lock.lockfileVersion, 1);
      expect(lock.registries['shadcn']?.namespace, 'shadcn');
      expect(lock.components, hasLength(1));

      final record = lock.components.single;
      expect(record.namespace, 'shadcn');
      expect(record.componentId, 'button');
      expect(record.qualifiedId, '@shadcn/button');
      expect(record.installedFiles,
          contains('lib/ui/shadcn/components/button/button.dart'));
      expect(record.installedFiles,
          contains('lib/ui/shadcn/components/button/meta.json'));
      expect(record.installedFiles,
          isNot(contains('lib/ui/shadcn/components/button/README.md')));
      expect(record.dependencies, {'skeletonizer': '^2.1.0+1'});
      expect(record.sourceManifestHash, isNotEmpty);

      final state = await ShadcnState.load(targetRoot.path);
      expect(state.managedDependencies, contains('data_widget'));
      expect(state.managedDependencies, contains('gap'));
    });

    test('fails before writes when another component owns generated target',
        () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          defaultNamespace: 'shadcn',
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeReadme: false,
          includeMeta: false,
          includePreview: false,
        ),
      );
      _writePubspec(targetRoot);
      _writeRawLock(
        targetRoot,
        components: [
          _rawLockComponent(
            namespace: 'other',
            componentId: 'card',
            installedFiles: [
              'lib/ui/shadcn/components/button/button.dart',
            ],
          ),
        ],
      );

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        registryNamespace: 'shadcn',
      );

      await expectLater(
        installer.addComponent('button'),
        throwsA(
          predicate(
            (Object error) =>
                error.toString().contains('Namespace collision') &&
                error
                    .toString()
                    .contains('lib/ui/shadcn/components/button/button.dart') &&
                error.toString().contains('@other/card') &&
                error.toString().contains('@shadcn/button'),
          ),
        ),
      );

      expect(
        File(p.join(
          targetRoot.path,
          'lib/ui/shadcn/components/button/button.dart',
        )).existsSync(),
        isFalse,
      );
    });

    test('fails when manifest namespace ownership collides', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          defaultNamespace: 'shadcn',
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeReadme: false,
          includeMeta: true,
          includePreview: false,
        ),
      );
      _writePubspec(targetRoot);
      _mutateRegistryJson(registryRoot, (json) {
        final components = json['components'] as List<dynamic>;
        final button = components
            .cast<Map<String, dynamic>>()
            .firstWhere((component) => component['id'] == 'button');
        button['assets'] = ['assets/fonts/shared.ttf'];
        button['manifestKeys'] = ['shared.button.label'];
        button['postInstallNamespaces'] = ['shared.bootstrap'];
        button['localeNamespaces'] = ['shared'];
      });
      _writeRawLock(
        targetRoot,
        components: [
          _rawLockComponent(
            namespace: 'other',
            componentId: 'card',
            assetPaths: ['assets/fonts/shared.ttf'],
            manifestKeys: ['shared.button.label'],
            postInstallNamespaces: ['shared.bootstrap'],
            localeNamespaces: ['shared'],
          ),
        ],
      );

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        registryNamespace: 'shadcn',
      );

      await expectLater(
        installer.addComponent('button'),
        throwsA(
          predicate(
            (Object error) =>
                error.toString().contains('Namespace collision') &&
                error.toString().contains('assets/fonts/shared.ttf') &&
                error.toString().contains('shared.button.label') &&
                error.toString().contains('shared.bootstrap') &&
                error.toString().contains('shared'),
          ),
        ),
      );
    });

    test('reinstalling same qualified component updates ownership record',
        () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          defaultNamespace: 'shadcn',
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeReadme: false,
          includeMeta: true,
          includePreview: false,
        ),
      );
      _writePubspec(targetRoot);
      _mutateRegistryJson(registryRoot, (json) {
        final components = json['components'] as List<dynamic>;
        final button = components
            .cast<Map<String, dynamic>>()
            .firstWhere((component) => component['id'] == 'button');
        button['assets'] = ['assets/fonts/shared.ttf'];
        button['manifestKeys'] = ['shadcn.button.label'];
        button['postInstallNamespaces'] = ['shadcn.button.bootstrap'];
        button['localeNamespaces'] = ['shadcn.button'];
      });
      _writeRawLock(
        targetRoot,
        components: [
          _rawLockComponent(
            namespace: 'shadcn',
            componentId: 'button',
            installedFiles: [
              'lib/ui/shadcn/components/button/button.dart',
              'lib/ui/shadcn/components/button/meta.json',
            ],
            assetPaths: ['assets/fonts/shared.ttf'],
            manifestKeys: ['shadcn.button.label'],
            postInstallNamespaces: ['shadcn.button.bootstrap'],
            localeNamespaces: ['shadcn.button'],
          ),
        ],
      );

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        registryNamespace: 'shadcn',
      );

      await installer.addComponent('button');

      final lock = await ShadcnLockRepository(targetRoot.path).load();
      final record = lock.componentFor(
        namespace: 'shadcn',
        componentId: 'button',
      );
      expect(record, isNotNull);
      expect(record!.installedFiles,
          contains('lib/ui/shadcn/components/button/button.dart'));
      expect(record.assetPaths, ['assets/fonts/shared.ttf']);
      expect(record.manifestKeys, ['shadcn.button.label']);
      expect(record.postInstallNamespaces, ['shadcn.button.bootstrap']);
      expect(record.localeNamespaces, ['shadcn.button']);
    });

    test('remove deletes lockfile record for removed component', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          defaultNamespace: 'shadcn',
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeReadme: false,
          includeMeta: true,
          includePreview: false,
        ),
      );
      _writePubspec(targetRoot);

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        registryNamespace: 'shadcn',
      );

      await installer.addComponent('button');
      await installer.removeComponent('button', force: true);

      final lock = await ShadcnLockRepository(targetRoot.path).load();
      expect(lock.components, isEmpty);
      final pubspec =
          File(p.join(targetRoot.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, isNot(contains('skeletonizer:')));
    });

    test('inserts dependencies when section missing', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeMeta: true,
        ),
      );
      File(p.join(targetRoot.path, 'pubspec.yaml')).writeAsStringSync(
        'name: test_app\nversion: 1.0.0\n',
      );

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        registryBaseUrlOverride: p.dirname(registryRoot.path),
        themesPathOverride: 'registry/manifests/theme.index.json',
      );

      await installer.addComponent('button');

      final pubspec =
          File(p.join(targetRoot.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec.contains('dependencies:'), isTrue);
      expect(pubspec.contains('skeletonizer: ^2.1.0+1'), isTrue);
    });

    test('fails when dependency is already present in dev_dependencies',
        () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeMeta: true,
        ),
      );
      File(p.join(targetRoot.path, 'pubspec.yaml')).writeAsStringSync(
        [
          'name: test_app',
          'environment:',
          '  sdk: ">=3.3.0 <4.0.0"',
          'dependencies:',
          '  flutter:',
          '    sdk: flutter',
          'dev_dependencies:',
          '  skeletonizer: ^2.1.0+1',
        ].join('\n'),
      );

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
      );

      await expectLater(
        installer.addComponent('button'),
        throwsA(
          predicate(
            (Object error) =>
                error.toString().contains('pubspec.yaml dependency conflict') &&
                error.toString().contains('skeletonizer'),
          ),
        ),
      );
    });

    test('fails when existing dependency constraint conflicts', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeMeta: true,
        ),
      );
      File(p.join(targetRoot.path, 'pubspec.yaml')).writeAsStringSync(
        [
          'name: test_app',
          'dependencies:',
          '  flutter:',
          '    sdk: flutter',
          '  skeletonizer: ^1.0.0',
        ].join('\n'),
      );

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
      );

      await expectLater(
        installer.addComponent('button'),
        throwsA(
          predicate(
            (Object error) =>
                error.toString().contains('pubspec.yaml dependency conflict') &&
                error.toString().contains('skeletonizer'),
          ),
        ),
      );

      final pubspec =
          File(p.join(targetRoot.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('skeletonizer: ^1.0.0'));
      expect(pubspec, isNot(contains('skeletonizer: ^2.1.0+1')));
      expect(
        File(
          p.join(
            targetRoot.path,
            'lib',
            'ui',
            'shadcn',
            'components',
            'button',
            'button.dart',
          ),
        ).existsSync(),
        isFalse,
      );
    });

    test('fails before writes when component dependency graph has a cycle',
        () async {
      _writePubspec(targetRoot);
      _mutateRegistryJson(registryRoot, (json) {
        final components = json['components'] as List<dynamic>;
        final button =
            components.cast<Map<String, dynamic>>().firstWhere((entry) {
          return entry['id'] == 'button';
        });
        button['dependsOn'] = ['dialog'];
      });

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
        skipIntegrity: true,
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
      );

      await expectLater(
        installer.addComponent('button'),
        throwsA(
          predicate(
            (Object error) =>
                error.toString().contains('dependency cycle') &&
                error.toString().contains('button -> dialog -> button'),
          ),
        ),
      );

      expect(
        File(
          p.join(
            targetRoot.path,
            'lib',
            'ui',
            'shadcn',
            'components',
            'button',
            'button.dart',
          ),
        ).existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(targetRoot.path, '.shadcn')).existsSync(),
        isFalse,
      );
    });

    test('dry-run fails when component dependency graph has a cycle', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeMeta: true,
        ),
      );
      _mutateRegistryJson(registryRoot, (json) {
        final components = json['components'] as List<dynamic>;
        final button =
            components.cast<Map<String, dynamic>>().firstWhere((entry) {
          return entry['id'] == 'button';
        });
        button['dependsOn'] = ['dialog'];
      });

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
        skipIntegrity: true,
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
      );

      await expectLater(
        installer.buildDryRunPlan(['button']),
        throwsA(
          predicate(
            (Object error) =>
                error.toString().contains('dependency cycle') &&
                error.toString().contains('button -> dialog -> button'),
          ),
        ),
      );
    });

    test('skips meta.json when includeMeta is false', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeMeta: false,
        ),
      );
      _writePubspec(targetRoot);

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
      );

      await installer.addComponent('button');

      final installDir = p.join(
        targetRoot.path,
        'lib',
        'ui',
        'shadcn',
        'components',
        'button',
      );

      expect(File(p.join(installDir, 'meta.json')).existsSync(), isFalse);
    });

    test('remove uses lockfile when meta tracking is disabled', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeMeta: false,
        ),
      );
      _writePubspec(targetRoot);

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
      );

      await installer.addComponent('button');
      await installer.removeComponent('button', force: true);

      final buttonFile = File(
        p.join(
          targetRoot.path,
          'lib',
          'ui',
          'shadcn',
          'components',
          'button',
          'button.dart',
        ),
      );
      final lock = await ShadcnLockRepository(targetRoot.path).load();

      expect(buttonFile.existsSync(), isFalse);
      expect(lock.components, isEmpty);
    });

    test('installs dependencies before component', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeMeta: true,
        ),
      );
      _writePubspec(targetRoot);

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
      );

      await installer.addComponent('dialog');

      final buttonFile = File(
        p.join(
          targetRoot.path,
          'lib',
          'ui',
          'shadcn',
          'components',
          'button',
          'button.dart',
        ),
      );
      final dialogFile = File(
        p.join(
          targetRoot.path,
          'lib',
          'ui',
          'shadcn',
          'components',
          'dialog',
          'dialog.dart',
        ),
      );

      expect(buttonFile.existsSync(), isTrue);
      expect(dialogFile.existsSync(), isTrue);
    });

    test('remove blocks when dependents exist', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeMeta: true,
        ),
      );
      _writePubspec(targetRoot);

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
      );

      await installer.addComponent('dialog');
      await installer.removeComponent('button');

      final buttonFile = File(
        p.join(
          targetRoot.path,
          'lib',
          'ui',
          'shadcn',
          'components',
          'button',
          'button.dart',
        ),
      );
      expect(buttonFile.existsSync(), isTrue);
    });

    test('force remove deletes component files', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeMeta: true,
        ),
      );
      _writePubspec(targetRoot);

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
      );

      await installer.addComponent('dialog');
      await installer.removeComponent('button', force: true);

      final buttonFile = File(
        p.join(
          targetRoot.path,
          'lib',
          'ui',
          'shadcn',
          'components',
          'button',
          'button.dart',
        ),
      );
      expect(buttonFile.existsSync(), isFalse);
    });

    test('init with overrides normalizes paths and aliases', () async {
      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
      );

      await installer.init(
        skipPrompts: true,
        configOverrides: const InitConfigOverrides(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeReadme: false,
          includeMeta: true,
          includePreview: false,
          classPrefix: 'App',
          pathAliases: {'ui': 'lib/ui'},
        ),
      );

      final config = await ShadcnConfig.load(targetRoot.path);
      expect(config.installPath, 'lib/ui/shadcn');
      expect(config.sharedPath, 'lib/ui/shadcn/shared');
      expect(config.pathAliases?['ui'], 'ui');
    });

    test('init auto-reuses existing config/state without prompts', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/custom',
          sharedPath: 'lib/ui/custom/shared',
          includeReadme: false,
          includeMeta: true,
          includePreview: false,
          defaultNamespace: 'shadcn',
          registries: {
            'shadcn': RegistryConfigEntry(
              installPath: 'lib/ui/custom',
              sharedPath: 'lib/ui/custom/shared',
              includeReadme: false,
              includeMeta: true,
              includePreview: false,
              enabled: true,
            ),
          },
        ),
      );
      await ShadcnState.save(
        targetRoot.path,
        const ShadcnState(
          installPath: 'lib/ui/custom',
          sharedPath: 'lib/ui/custom/shared',
          registries: {
            'shadcn': RegistryStateEntry(
              installPath: 'lib/ui/custom',
              sharedPath: 'lib/ui/custom/shared',
            ),
          },
        ),
      );
      _writePubspec(targetRoot);

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );
      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
      );

      await installer.init();

      expect(
        File(
          p.join(
            targetRoot.path,
            'lib',
            'ui',
            'custom',
            'shared',
            'theme',
            'theme.dart',
          ),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(
            targetRoot.path,
            '.shadcn',
            'config.json',
          ),
        ).existsSync(),
        isTrue,
      );
    });

    test('applies theme artifact manifest and updates config theme id',
        () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeReadme: false,
          includeMeta: true,
          includePreview: false,
        ),
      );
      _writePubspec(targetRoot);

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );
      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        registryBaseUrlOverride: p.dirname(registryRoot.path),
        themesPathOverride: 'registry/manifests/theme.index.json',
      );

      await installer.init(skipPrompts: true);
      await installer.applyThemeById('modern-minimal');

      final generatedThemeFile = File(
        p.join(
          targetRoot.path,
          'lib',
          'ui',
          'shadcn',
          'shared',
          'theme',
          '_impl',
          'core',
          'generated_modern_minimal_theme.dart',
        ),
      );
      expect(generatedThemeFile.existsSync(), isTrue);
      final config = await ShadcnConfig.load(targetRoot.path);
      expect(config.themeId, 'modern-minimal');
    });

    test('aborts theme install before writes when artifact hash mismatches',
        () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeReadme: false,
          includeMeta: true,
          includePreview: false,
        ),
      );
      _writePubspec(targetRoot);

      final manifestFile = File(
        p.join(
          registryRoot.path,
          'manifests',
          'themes_preset',
          'modern-minimal.json',
        ),
      );
      final manifestData =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      final files =
          (manifestData['files'] as List).cast<Map<String, dynamic>>();
      files[0] = {
        ...files[0],
        'sha256': '0' * 64,
      };
      manifestFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(manifestData),
      );

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );
      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        registryBaseUrlOverride: p.dirname(registryRoot.path),
        themesPathOverride: 'registry/manifests/theme.index.json',
      );

      await installer.init(skipPrompts: true);

      final generatedThemeFile = File(
        p.join(
          targetRoot.path,
          'lib',
          'ui',
          'shadcn',
          'shared',
          'theme',
          '_impl',
          'core',
          'generated_modern_minimal_theme.dart',
        ),
      );
      expect(generatedThemeFile.existsSync(), isFalse);

      await expectLater(
        installer.applyThemeById('modern-minimal'),
        throwsA(
          isA<ThemeInstallException>()
              .having((error) => error.code, 'code', 'hash-mismatch')
              .having((error) => error.message, 'message', contains('SHA-256')),
        ),
      );
      expect(generatedThemeFile.existsSync(), isFalse);
    });

    test('theme artifact failures expose typed error codes', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeReadme: false,
          includeMeta: true,
          includePreview: false,
        ),
      );
      _writePubspec(targetRoot);

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );
      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
      );

      await expectLater(
        installer.applyThemeFromJson({
          'id': 'bad-source',
          'name': 'Bad Source',
          'files': [
            {
              'source': 'ftp://example.com/theme.dart',
              'target':
                  '{sharedPath}/theme/_impl/core/generated_bad_source.dart',
              'sha256': '00',
            }
          ],
        }),
        throwsA(
          isA<ThemeInstallException>()
              .having((error) => error.code, 'code', 'unsupported-source')
              .having(
                (error) => error.message,
                'message',
                contains('Unsupported theme artifact source'),
              ),
        ),
      );
    });

    test('rejects dangerous theme manifest targets before writes', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeReadme: false,
          includeMeta: true,
          includePreview: false,
        ),
      );
      _writePubspec(targetRoot);

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );
      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
      );

      final artifactFile = File(
        p.join(
          registryRoot.path,
          'shared',
          'theme',
          '_impl',
          'core',
          'color_schemes.dart',
        ),
      );
      final digest = sha256.convert(artifactFile.readAsBytesSync()).toString();

      await expectLater(
        installer.applyThemeFromJson({
          'id': 'escape-theme',
          'name': 'Escape Theme',
          'files': [
            {
              'source': 'registry/shared/theme/_impl/core/color_schemes.dart',
              'target': '../escape.dart',
              'sha256': digest,
            }
          ],
        }),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('escapes project root'),
          ),
        ),
      );
      expect(File(p.join(tempRoot.path, 'escape.dart')).existsSync(), isFalse);
    });
  });
}

void _writeRegistryFixtures(Directory registryRoot) {
  final root = p.dirname(registryRoot.path);
  final componentsDir =
      Directory(p.join(root, 'registry', 'components', 'button'))
        ..createSync(recursive: true);
  final dialogDir = Directory(p.join(root, 'registry', 'components', 'dialog'))
    ..createSync(recursive: true);
  final sharedThemeDir = Directory(p.join(root, 'registry', 'shared', 'theme'))
    ..createSync(recursive: true);
  final sharedThemeImplCoreDir =
      Directory(p.join(root, 'registry', 'shared', 'theme', '_impl', 'core'))
        ..createSync(recursive: true);
  final sharedUtilDir = Directory(p.join(root, 'registry', 'shared', 'util'))
    ..createSync(recursive: true);
  final sharedColorExtensionsDir =
      Directory(p.join(root, 'registry', 'shared', 'color_extensions'))
        ..createSync(recursive: true);
  final sharedFormControlDir =
      Directory(p.join(root, 'registry', 'shared', 'form_control'))
        ..createSync(recursive: true);
  final sharedFormValueSupplierDir =
      Directory(p.join(root, 'registry', 'shared', 'form_value_supplier'))
        ..createSync(recursive: true);

  File(p.join(componentsDir.path, 'button.dart'))
      .writeAsStringSync('class Button {}');
  File(p.join(componentsDir.path, 'README.md')).writeAsStringSync('# Button');
  File(p.join(componentsDir.path, 'meta.json')).writeAsStringSync(
    jsonEncode({
      'id': 'button',
      'name': 'Button',
      'files': [
        {
          'source': 'registry/components/button/button.dart',
          'destination': '{installPath}/components/button/button.dart'
        },
        {
          'source': 'registry/components/button/README.md',
          'destination': '{installPath}/components/button/README.md'
        },
        {
          'source': 'registry/components/button/meta.json',
          'destination': '{installPath}/components/button/meta.json'
        },
        {
          'source': 'registry/components/button/preview.dart',
          'destination': '{installPath}/components/button/preview.dart'
        },
        {
          'source': 'registry/components/button/preview_state.dart',
          'destination': '{installPath}/components/button/preview_state.dart'
        }
      ],
      'shared': [],
      'dependsOn': [],
      'pubspec': {
        'dependencies': {'skeletonizer': '^2.1.0+1'}
      },
      'assets': [],
      'fonts': [],
      'postInstall': [],
    }),
  );
  File(p.join(componentsDir.path, 'preview.dart'))
      .writeAsStringSync('void main() {}');
  File(p.join(componentsDir.path, 'preview_state.dart'))
      .writeAsStringSync('class PreviewState {}');

  File(p.join(dialogDir.path, 'dialog.dart'))
      .writeAsStringSync('class Dialog {}');
  File(p.join(dialogDir.path, 'meta.json')).writeAsStringSync(
    jsonEncode({
      'id': 'dialog',
      'name': 'Dialog',
      'files': [
        {
          'source': 'registry/components/dialog/dialog.dart',
          'destination': '{installPath}/components/dialog/dialog.dart'
        },
        {
          'source': 'registry/components/dialog/meta.json',
          'destination': '{installPath}/components/dialog/meta.json'
        }
      ],
      'shared': [],
      'dependsOn': ['button'],
      'pubspec': {'dependencies': {}},
      'assets': [],
      'fonts': [],
      'postInstall': [],
    }),
  );

  File(p.join(sharedThemeDir.path, 'theme.dart'))
      .writeAsStringSync('class ThemeHelper {}');
  File(p.join(sharedThemeImplCoreDir.path, 'color_schemes.dart'))
      .writeAsStringSync(
    '''
import 'package:flutter/material.dart';

class ColorSchemes {
  static const ColorScheme lightDefaultColor = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF111111),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF222222),
    onSecondary: Color(0xFFFFFFFF),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF111111),
  );

  static const ColorScheme darkDefaultColor = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFEEEEEE),
    onPrimary: Color(0xFF111111),
    secondary: Color(0xFFDDDDDD),
    onSecondary: Color(0xFF111111),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    surface: Color(0xFF111111),
    onSurface: Color(0xFFEEEEEE),
  );
}
''',
  );
  File(p.join(sharedUtilDir.path, 'util.dart'))
      .writeAsStringSync('class UtilHelper {}');
  File(p.join(sharedColorExtensionsDir.path, 'color_extensions.dart'))
      .writeAsStringSync('class ColorExtensions {}');
  File(p.join(sharedFormControlDir.path, 'form_control.dart'))
      .writeAsStringSync('class FormControl {}');
  File(p.join(sharedFormValueSupplierDir.path, 'form_value_supplier.dart'))
      .writeAsStringSync('class FormValueSupplier {}');

  final registryJson = {
    'defaults': {
      'installPath': 'lib/ui/shadcn',
      'sharedPath': 'lib/ui/shadcn/shared',
    },
    'shared': [
      {
        'id': 'theme',
        'files': [
          {
            'source': 'registry/shared/theme/theme.dart',
            'destination': '{sharedPath}/theme/theme.dart'
          },
          {
            'source': 'registry/shared/theme/_impl/core/color_schemes.dart',
            'destination': '{sharedPath}/theme/_impl/core/color_schemes.dart'
          }
        ]
      },
      {
        'id': 'util',
        'files': [
          {
            'source': 'registry/shared/util/util.dart',
            'destination': '{sharedPath}/util/util.dart'
          }
        ]
      },
      {
        'id': 'color_extensions',
        'files': [
          {
            'source': 'registry/shared/color_extensions/color_extensions.dart',
            'destination': '{sharedPath}/color_extensions/color_extensions.dart'
          }
        ]
      },
      {
        'id': 'form_control',
        'files': [
          {
            'source': 'registry/shared/form_control/form_control.dart',
            'destination': '{sharedPath}/form_control/form_control.dart'
          }
        ]
      },
      {
        'id': 'form_value_supplier',
        'files': [
          {
            'source':
                'registry/shared/form_value_supplier/form_value_supplier.dart',
            'destination':
                '{sharedPath}/form_value_supplier/form_value_supplier.dart'
          }
        ]
      }
    ],
    'components': [
      {
        'id': 'button',
        'name': 'Button',
        'files': [
          {
            'source': 'registry/components/button/button.dart',
            'destination': '{installPath}/components/button/button.dart'
          },
          {
            'source': 'registry/components/button/README.md',
            'destination': '{installPath}/components/button/README.md'
          },
          {
            'source': 'registry/components/button/meta.json',
            'destination': '{installPath}/components/button/meta.json'
          },
          {
            'source': 'registry/components/button/preview.dart',
            'destination': '{installPath}/components/button/preview.dart'
          },
          {
            'source': 'registry/components/button/preview_state.dart',
            'destination': '{installPath}/components/button/preview_state.dart'
          }
        ],
        'shared': [],
        'dependsOn': [],
        'pubspec': {
          'dependencies': {'skeletonizer': '^2.1.0+1'}
        }
      },
      {
        'id': 'dialog',
        'name': 'Dialog',
        'files': [
          {
            'source': 'registry/components/dialog/dialog.dart',
            'destination': '{installPath}/components/dialog/dialog.dart'
          },
          {
            'source': 'registry/components/dialog/meta.json',
            'destination': '{installPath}/components/dialog/meta.json'
          }
        ],
        'shared': [],
        'dependsOn': ['button'],
        'pubspec': {'dependencies': {}}
      }
    ]
  };

  File(p.join(registryRoot.path, 'components.json')).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(registryJson));
  File(p.join(registryRoot.path, 'components.schema.json'))
      .writeAsStringSync(jsonEncode({}));

  File(p.join(registryRoot.path, 'manifests', 'theme.index.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'themes': [
          {
            'id': 'modern-minimal',
            'name': 'Modern Minimal',
            'file': 'themes_preset/modern-minimal.json',
          }
        ],
      }),
    );

  final generatedThemeFile = File(
    p.join(
      registryRoot.path,
      'shared',
      'theme',
      '_impl',
      'core',
      'generated_modern_minimal_theme.dart',
    ),
  )..writeAsStringSync(
      "const generatedModernMinimalTheme = 'modern-minimal';\n",
    );
  final generatedThemeDigest =
      sha256.convert(generatedThemeFile.readAsBytesSync()).toString();

  File(p.join(
      registryRoot.path, 'manifests', 'themes_preset', 'modern-minimal.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'id': 'modern-minimal',
        'name': 'Modern Minimal',
        'files': [
          {
            'source':
                'registry/shared/theme/_impl/core/generated_modern_minimal_theme.dart',
            'target':
                '{sharedPath}/theme/_impl/core/generated_modern_minimal_theme.dart',
            'sha256': generatedThemeDigest,
          }
        ],
      }),
    );
}

void _mutateRegistryJson(
  Directory registryRoot,
  void Function(Map<String, dynamic> json) mutate,
) {
  final file = File(p.join(registryRoot.path, 'components.json'));
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  mutate(json);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  for (final component
      in (json['components'] as List).cast<Map<String, dynamic>>()) {
    final id = component['id'] as String;
    final manifest = File(
      p.join(p.dirname(registryRoot.path), 'registry', 'components', id,
          'meta.json'),
    );
    if (manifest.existsSync()) {
      manifest.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(component),
      );
    }
  }
}

void _writeRawLock(
  Directory targetRoot, {
  required List<Map<String, dynamic>> components,
}) {
  File(p.join(targetRoot.path, 'shadcn.lock')).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'lockfileVersion': 1,
      'registries': {
        'shadcn': {
          'namespace': 'shadcn',
          'registryRoot': '/tmp/shadcn',
          'sourceRoot': '/tmp/shadcn',
          'sourceManifestHash': 'hash',
        },
        'other': {
          'namespace': 'other',
          'registryRoot': '/tmp/other',
          'sourceRoot': '/tmp/other',
          'sourceManifestHash': 'hash',
        },
      },
      'components': components,
    }),
  );
}

Map<String, dynamic> _rawLockComponent({
  required String namespace,
  required String componentId,
  List<String> installedFiles = const [],
  List<String> assetPaths = const [],
  List<String> manifestKeys = const [],
  List<String> postInstallNamespaces = const [],
  List<String> localeNamespaces = const [],
}) {
  return {
    'namespace': namespace,
    'componentId': componentId,
    'qualifiedId': '@$namespace/$componentId',
    'version': '1.0.0',
    'registryRoot': '/tmp/$namespace',
    'sourceManifestHash': 'hash',
    'installedFiles': installedFiles,
    'dependencies': {},
    'postInstall': [],
    'localeKeys': [],
    'assetPaths': assetPaths,
    'manifestKeys': manifestKeys,
    'postInstallNamespaces': postInstallNamespaces,
    'localeNamespaces': localeNamespaces,
  };
}

void _writePubspec(Directory targetRoot, {Map<String, String>? dependencies}) {
  final buffer = StringBuffer()
    ..writeln('name: test_app')
    ..writeln('environment:')
    ..writeln('  sdk: ">=3.3.0 <4.0.0"')
    ..writeln('dependencies:');
  final deps = dependencies ??
      {
        'flutter': 'sdk: flutter',
      };
  deps.forEach((key, value) {
    buffer.writeln('  $key: $value');
  });
  File(p.join(targetRoot.path, 'pubspec.yaml'))
      .writeAsStringSync(buffer.toString());
}

Future<void> _writeConfig(Directory targetRoot, ShadcnConfig config) async {
  await ShadcnConfig.save(targetRoot.path, config);
}
