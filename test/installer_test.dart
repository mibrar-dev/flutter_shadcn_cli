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

    test('adds exact copied asset file to pubspec instead of directory entry',
        () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          defaultNamespace: 'shadcn',
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeMeta: true,
        ),
      );
      _writePubspec(targetRoot);
      _addAssetComponent(registryRoot, assets: ['assets/']);

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
        skipIntegrity: true,
      );

      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        registryNamespace: 'shadcn',
      );

      await installer.addComponent('logo_asset');

      final pubspec =
          File(p.join(targetRoot.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('assets/logo.svg'));
      expect(pubspec, isNot(contains('    - assets/\n')));

      final lock = await ShadcnLockRepository(targetRoot.path).load();
      final record = lock.componentFor(
        namespace: 'shadcn',
        componentId: 'logo_asset',
      );
      expect(record?.installedFiles, contains('assets/logo.svg'));
    });

    test('preserves existing asset and does not add it to pubspec or lockfile',
        () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          defaultNamespace: 'shadcn',
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeMeta: true,
        ),
      );
      _writePubspec(targetRoot);
      _addAssetComponent(registryRoot, assets: ['assets/logo.svg']);
      final existingAsset = File(p.join(targetRoot.path, 'assets', 'logo.svg'))
        ..createSync(recursive: true)
        ..writeAsStringSync('<svg>user</svg>');

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
        skipIntegrity: true,
      );
      final logger = _RecordingLogger();
      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: logger,
        registryNamespace: 'shadcn',
      );

      await installer.addComponent('logo_asset');

      expect(existingAsset.readAsStringSync(), '<svg>user</svg>');
      expect(logger.warnings,
          contains(contains('Preserved existing asset assets/logo.svg')));
      final pubspec =
          File(p.join(targetRoot.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, isNot(contains('assets/logo.svg')));

      final lock = await ShadcnLockRepository(targetRoot.path).load();
      final record = lock.componentFor(
        namespace: 'shadcn',
        componentId: 'logo_asset',
      );
      expect(record?.installedFiles, isNot(contains('assets/logo.svg')));
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
          installPath: 'ui/shadcn',
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
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('SHA-256'),
          ),
        ),
      );
      expect(generatedThemeFile.existsSync(), isFalse);
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
  File(p.join(componentsDir.path, 'meta.json'))
      .writeAsStringSync('{"id":"button"}');
  File(p.join(componentsDir.path, 'preview.dart'))
      .writeAsStringSync('void main() {}');
  File(p.join(componentsDir.path, 'preview_state.dart'))
      .writeAsStringSync('class PreviewState {}');

  File(p.join(dialogDir.path, 'dialog.dart'))
      .writeAsStringSync('class Dialog {}');
  File(p.join(dialogDir.path, 'meta.json'))
      .writeAsStringSync('{"id":"dialog"}');

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
}

void _addAssetComponent(
  Directory registryRoot, {
  required List<String> assets,
}) {
  File(p.join(registryRoot.path, 'assets', 'logo.svg'))
    ..createSync(recursive: true)
    ..writeAsStringSync('<svg>registry</svg>');
  _mutateRegistryJson(registryRoot, (json) {
    final components = json['components'] as List<dynamic>;
    components.add({
      'id': 'logo_asset',
      'name': 'Logo Asset',
      'files': [
        {
          'source': 'registry/assets/logo.svg',
          'destination': 'assets/logo.svg',
        }
      ],
      'shared': [],
      'dependsOn': [],
      'pubspec': {'dependencies': {}},
      'assets': assets,
    });
  });
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

class _RecordingLogger extends CliLogger {
  final List<String> warnings = [];

  _RecordingLogger() : super(useColor: false);

  @override
  void warn(String message) {
    warnings.add(message);
  }
}
