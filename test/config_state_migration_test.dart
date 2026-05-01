import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/state.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('config and state normalization', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('shadcn_normalize_test_');
      Directory(p.join(tempDir.path, '.shadcn')).createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('normalizes older-shaped config to registries map', () async {
      final oldConfig =
          File('test/fixtures/old_config.json').readAsStringSync();
      final configFile = File(p.join(tempDir.path, '.shadcn', 'config.json'));
      configFile.writeAsStringSync(oldConfig);

      final config = await ShadcnConfig.load(tempDir.path);
      expect(config.effectiveDefaultNamespace, 'shadcn');
      expect(config.registries, isNotNull);
      expect(config.registries!.containsKey('shadcn'), isTrue);
      expect(config.registryUrl, 'https://example.com/registry');
      expect(config.installPath, 'lib/ui/shadcn');
      expect(config.sharedPath, 'lib/ui/shadcn/shared');
      expect(config.includeFiles, ['meta']);
      expect(config.excludeFiles, ['preview']);

      final normalizedJson =
          jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
      expect(normalizedJson['registries'], isA<Map>());
      expect(normalizedJson['defaultNamespace'], 'shadcn');
      final shadcn = (normalizedJson['registries'] as Map)['shadcn'] as Map;
      expect(shadcn['registryUrl'], 'https://example.com/registry');
      expect(shadcn['includeFiles'], ['meta']);
      expect(shadcn['excludeFiles'], ['preview']);
    });

    test('loads new config format fixture', () async {
      final newConfig =
          File('test/fixtures/new_config.json').readAsStringSync();
      final configFile = File(p.join(tempDir.path, '.shadcn', 'config.json'));
      configFile.writeAsStringSync(newConfig);

      final config = await ShadcnConfig.load(tempDir.path);
      expect(config.registries, isNotNull);
      expect(config.registries!['shadcn']?.enabled, isTrue);
      expect(config.installPath, 'lib/ui/shadcn');
      expect(config.sharedPath, 'lib/ui/shadcn/shared');
      expect(config.includeFiles, ['meta']);
      expect(config.excludeFiles, ['preview']);
    });

    test('normalizes older-shaped state to registries map', () async {
      final oldState = File('test/fixtures/old_state.json').readAsStringSync();
      final stateFile = File(p.join(tempDir.path, '.shadcn', 'state.json'));
      stateFile.writeAsStringSync(oldState);

      final state = await ShadcnState.load(tempDir.path);
      expect(state.registries, isNotNull);
      expect(state.registries!['shadcn'], isNotNull);
      expect(state.installPath, 'lib/ui/shadcn');
      expect(state.sharedPath, 'lib/ui/shadcn/shared');
      expect(state.managedDependencies, containsAll(['gap', 'data_widget']));

      final normalizedJson =
          jsonDecode(stateFile.readAsStringSync()) as Map<String, dynamic>;
      expect(normalizedJson['registries'], isA<Map>());
      expect(
        ((normalizedJson['registries'] as Map)['shadcn'] as Map)['installPath'],
        'lib/ui/shadcn',
      );
      expect(
        normalizedJson['managedDependencies'],
        containsAll(['gap', 'data_widget']),
      );
    });

    test('loads new state format fixture', () async {
      final newState = File('test/fixtures/new_state.json').readAsStringSync();
      final stateFile = File(p.join(tempDir.path, '.shadcn', 'state.json'));
      stateFile.writeAsStringSync(newState);

      final state = await ShadcnState.load(tempDir.path);
      expect(state.registries, isNotNull);
      expect(state.registries!['shadcn']?.themeId, 'modern-minimal');
      expect(state.managedDependencies, containsAll(['gap', 'data_widget']));
    });

    test('missing config and state files load empty defaults', () async {
      final configPath = p.join(tempDir.path, '.shadcn', 'config.json');
      if (File(configPath).existsSync()) {
        File(configPath).deleteSync();
      }
      final statePath = p.join(tempDir.path, '.shadcn', 'state.json');
      if (File(statePath).existsSync()) {
        File(statePath).deleteSync();
      }

      final config = await ShadcnConfig.load(tempDir.path);
      final state = await ShadcnState.load(tempDir.path);

      expect(config.registries, isNull);
      expect(state.registries, isNull);
    });

    test('invalid config json throws typed load error', () async {
      final configFile = File(p.join(tempDir.path, '.shadcn', 'config.json'));
      configFile.writeAsStringSync('{not-json');

      await expectLater(
        () => ShadcnConfig.load(tempDir.path),
        throwsA(isA<ShadcnConfigLoadException>()),
      );
    });

    test('invalid state json throws typed load error', () async {
      final stateFile = File(p.join(tempDir.path, '.shadcn', 'state.json'));
      stateFile.writeAsStringSync('{not-json');

      await expectLater(
        () => ShadcnState.load(tempDir.path),
        throwsA(isA<ShadcnStateLoadException>()),
      );
    });
  });
}
