import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/application/services/command_health/audit_command.dart';
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

    test('upgrades legacy bare component manifest to namespaced manifest',
        () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          defaultNamespace: 'shadcn',
          registries: {
            'shadcn': RegistryConfigEntry(
              installPath: 'lib/ui/shadcn',
              sharedPath: 'lib/ui/shadcn/shared',
              includeReadme: true,
              includeMeta: true,
              includePreview: true,
              enabled: true,
            ),
          },
        ),
      );
      _writePubspec(targetRoot);
      final legacyManifest = File(
        p.join(targetRoot.path, '.shadcn', 'components', 'button.json'),
      );
      legacyManifest.parent.createSync(recursive: true);
      legacyManifest.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': 1,
          'id': 'button',
          'installedAt': '2026-01-02T03:04:05.000Z',
        }),
      );

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );
      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        stateNamespace: 'shadcn',
        registryNamespace: 'shadcn',
      );

      await installer.addComponent('button');

      final nextManifest = File(
        p.join(
          targetRoot.path,
          '.shadcn',
          'components',
          'shadcn',
          'button.json',
        ),
      );
      expect(nextManifest.existsSync(), isTrue);
      expect(legacyManifest.existsSync(), isFalse);
      final data =
          jsonDecode(nextManifest.readAsStringSync()) as Map<String, dynamic>;
      expect(data['namespace'], 'shadcn');
      expect(data['componentId'], 'button');
      expect(data['qualifiedId'], '@shadcn/button');
      expect(data['installedAt'], '2026-01-02T03:04:05.000Z');
    });

    test('remove keeps other namespace manifest with same component id',
        () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          defaultNamespace: 'shadcn',
          registries: {
            'shadcn': RegistryConfigEntry(
              installPath: 'lib/ui/shadcn',
              sharedPath: 'lib/ui/shadcn/shared',
              includeReadme: true,
              includeMeta: true,
              includePreview: true,
              enabled: true,
            ),
            'alt': RegistryConfigEntry(
              installPath: 'lib/ui/alt',
              sharedPath: 'lib/ui/alt/shared',
              includeMeta: true,
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
      final shadcnInstaller = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        stateNamespace: 'shadcn',
        registryNamespace: 'shadcn',
        installPathOverride: 'lib/ui/shadcn',
        sharedPathOverride: 'lib/ui/shadcn/shared',
      );
      final altInstaller = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        stateNamespace: 'alt',
        registryNamespace: 'alt',
        installPathOverride: 'lib/ui/alt',
        sharedPathOverride: 'lib/ui/alt/shared',
      );

      await shadcnInstaller.addComponent('button');
      await altInstaller.addComponent('button');
      await shadcnInstaller.removeComponent('button', force: true);

      expect(
        File(
          p.join(
            targetRoot.path,
            '.shadcn',
            'components',
            'shadcn',
            'button.json',
          ),
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          p.join(
            targetRoot.path,
            '.shadcn',
            'components',
            'alt',
            'button.json',
          ),
        ).existsSync(),
        isTrue,
      );
    });

    test('remove all keeps other namespace manifests and config state',
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
              enabled: true,
            ),
            'alt': RegistryConfigEntry(
              installPath: 'lib/ui/alt',
              sharedPath: 'lib/ui/alt/shared',
              includeMeta: true,
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
      final shadcnInstaller = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        stateNamespace: 'shadcn',
        registryNamespace: 'shadcn',
        installPathOverride: 'lib/ui/shadcn',
        sharedPathOverride: 'lib/ui/shadcn/shared',
      );
      final altInstaller = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        stateNamespace: 'alt',
        registryNamespace: 'alt',
        installPathOverride: 'lib/ui/alt',
        sharedPathOverride: 'lib/ui/alt/shared',
      );

      await shadcnInstaller.addComponent('button');
      await altInstaller.addComponent('button');
      await shadcnInstaller.removeAllComponents();

      expect(
        File(
          p.join(
            targetRoot.path,
            '.shadcn',
            'components',
            'shadcn',
            'button.json',
          ),
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          p.join(
            targetRoot.path,
            '.shadcn',
            'components',
            'alt',
            'button.json',
          ),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(targetRoot.path, '.shadcn', 'config.json')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(targetRoot.path, '.shadcn', 'state.json')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(targetRoot.path, 'pubspec.yaml')).readAsStringSync(),
        contains('skeletonizer:'),
      );
      final state = await ShadcnState.load(targetRoot.path);
      expect(state.managedDependencies, contains('skeletonizer'));
    });

    test('audit reads namespaced component manifests', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          defaultNamespace: 'shadcn',
          registries: {
            'shadcn': RegistryConfigEntry(
              installPath: 'lib/ui/shadcn',
              sharedPath: 'lib/ui/shadcn/shared',
              includeReadme: true,
              includeMeta: true,
              includePreview: true,
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
        stateNamespace: 'shadcn',
        registryNamespace: 'shadcn',
      );
      await installer.addComponent('button');

      final printed = <String>[];
      final exitCode = await runZoned(
        () async => runAuditCommand(
          registry: registry,
          targetDir: targetRoot.path,
          config: await ShadcnConfig.load(targetRoot.path),
          jsonOutput: true,
          logger: CliLogger(),
        ),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => printed.add(line),
        ),
      );

      expect(exitCode, ExitCodes.success);
      final payload = jsonDecode(printed.join('\n')) as Map<String, dynamic>;
      final data = payload['data'] as Map<String, dynamic>;
      expect(data['installed'], contains('button'));
    });

    test('audit uses selected namespace instead of default namespace',
        () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          defaultNamespace: 'shadcn',
          registries: {
            'shadcn': RegistryConfigEntry(
              installPath: 'lib/ui/shadcn',
              sharedPath: 'lib/ui/shadcn/shared',
              includeReadme: true,
              includeMeta: true,
              includePreview: true,
              enabled: true,
            ),
            'alt': RegistryConfigEntry(
              installPath: 'lib/ui/alt',
              sharedPath: 'lib/ui/alt/shared',
              includeReadme: true,
              includeMeta: true,
              includePreview: true,
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
      final altInstaller = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        stateNamespace: 'alt',
        registryNamespace: 'alt',
        installPathOverride: 'lib/ui/alt',
        sharedPathOverride: 'lib/ui/alt/shared',
      );
      await altInstaller.addComponent('button');

      final printed = <String>[];
      final exitCode = await runZoned(
        () async => runAuditCommand(
          registry: registry,
          targetDir: targetRoot.path,
          config: await ShadcnConfig.load(targetRoot.path),
          registryNamespace: 'alt',
          jsonOutput: true,
          logger: CliLogger(),
        ),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => printed.add(line),
        ),
      );

      expect(exitCode, ExitCodes.success);
      final payload = jsonDecode(printed.join('\n')) as Map<String, dynamic>;
      final data = payload['data'] as Map<String, dynamic>;
      expect(data['installed'], ['button']);
    });

    test('remove cleans up manifest-only namespaced install', () async {
      await _writeConfig(
        targetRoot,
        const ShadcnConfig(
          defaultNamespace: 'shadcn',
          registries: {
            'shadcn': RegistryConfigEntry(
              installPath: 'lib/ui/shadcn',
              sharedPath: 'lib/ui/shadcn/shared',
              includeMeta: true,
              enabled: true,
            ),
          },
        ),
      );
      _writePubspec(targetRoot);
      final manifest = File(
        p.join(
          targetRoot.path,
          '.shadcn',
          'components',
          'shadcn',
          'button.json',
        ),
      );
      manifest.parent.createSync(recursive: true);
      manifest.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': 1,
          'id': 'button',
          'namespace': 'shadcn',
          'componentId': 'button',
          'qualifiedId': '@shadcn/button',
        }),
      );

      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
      );
      final installer = Installer(
        registry: registry,
        targetDir: targetRoot.path,
        logger: CliLogger(),
        stateNamespace: 'shadcn',
        registryNamespace: 'shadcn',
      );

      await installer.removeComponent('button', force: true);

      expect(manifest.existsSync(), isFalse);
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

    test('does not duplicate dependency present in dev_dependencies', () async {
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

      await installer.addComponent('button');

      final pubspec =
          File(p.join(targetRoot.path, 'pubspec.yaml')).readAsStringSync();
      final occurrences = RegExp('skeletonizer:').allMatches(pubspec).length;
      expect(occurrences, 1);
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
