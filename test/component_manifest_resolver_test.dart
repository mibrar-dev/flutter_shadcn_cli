import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/component_manifest_resolver.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ComponentManifestResolver', () {
    late Directory tempRoot;
    late Directory registryRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('manifest_resolver_');
      registryRoot = Directory(p.join(tempRoot.path, 'registry'))
        ..createSync(recursive: true);
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('prefers category component-local meta over components.json',
        () async {
      _writeComponentsJson(
        registryRoot,
        component: _componentJson(
          id: 'button',
          name: 'Button From Components Json',
          category: 'control',
          shared: const [],
          dependencies: const {},
        ),
      );
      final metaDir = Directory(
          p.join(registryRoot.path, 'components', 'control', 'button'))
        ..createSync(recursive: true);
      File(p.join(metaDir.path, 'meta.json')).writeAsStringSync(
        jsonEncode(
          _componentJson(
            id: 'button',
            name: 'Button From Meta',
            category: 'control',
            shared: const ['clickable'],
            dependencies: const {'gap': '^3.0.1'},
          ),
        ),
      );

      final registry = await _loadRegistry(registryRoot);
      final resolver = ComponentManifestResolver(
        registry: registry,
        logger: CliLogger(verbose: true),
      );

      final resolved = await resolver.resolve('button');

      expect(resolved, isNotNull);
      expect(resolved!.name, 'Button From Meta');
      expect(resolved.shared, ['clickable']);
      expect(resolved.pubspec['dependencies']['gap'], '^3.0.1');
    });

    test('normalizes kit-style component meta and skips docs meta', () async {
      _writeComponentsJson(
        registryRoot,
        component: _componentJson(
          id: 'button',
          name: 'Button From Components Json',
          category: 'control',
          shared: const [],
          dependencies: const {},
        ),
      );
      final metaDir = Directory(
          p.join(registryRoot.path, 'components', 'control', 'button'))
        ..createSync(recursive: true);
      File(p.join(metaDir.path, 'button.meta.json')).writeAsStringSync(
        jsonEncode({
          r'$schema': '../../../manifests/readme_meta.schema.json',
          'id': 'button',
          'name': 'Button Docs',
          'whenToUse': {
            'use': ['documentation only'],
          },
        }),
      );
      File(p.join(metaDir.path, 'meta.json')).writeAsStringSync(
        jsonEncode({
          'id': 'button',
          'name': 'Button From Local Meta',
          'description': 'Kit registry install metadata.',
          'category': 'control',
          'tags': ['controls'],
          'dependencies': {
            'shared': ['theme', 'clickable'],
            'components': ['spinner'],
            'pubspec': {'gap': '^3.0.1'},
          },
          'files': [
            '_impl/core/button_core.dart',
            'button.dart',
          ],
          'postInstall': ['Use the shared theme.'],
        }),
      );

      final registry = await _loadRegistry(registryRoot);
      final resolver = ComponentManifestResolver(registry: registry);

      final resolved = await resolver.resolve('button');

      expect(resolved, isNotNull);
      expect(resolved!.name, 'Button From Local Meta');
      expect(resolved.shared, ['theme', 'clickable']);
      expect(resolved.dependsOn, ['spinner']);
      expect(resolved.pubspec['dependencies']['gap'], '^3.0.1');
      expect(
        resolved.files.first.source,
        'registry/components/control/button/_impl/core/button_core.dart',
      );
      expect(
        resolved.files.first.destination,
        '{installPath}/components/control/button/_impl/core/button_core.dart',
      );
    });

    test('falls back to components.json when registry has no local manifests',
        () async {
      _writeComponentsJson(
        registryRoot,
        component: _componentJson(
          id: 'button',
          name: 'Button From Components Json',
          category: 'control',
          shared: const ['from_components_json'],
          dependencies: const {},
        ),
      );

      final registry = await _loadRegistry(registryRoot);
      final resolver = ComponentManifestResolver(registry: registry);

      final resolved = await resolver.resolve('button');

      expect(resolved, isNotNull);
      expect(resolved!.name, 'Button From Components Json');
      expect(resolved.shared, ['from_components_json']);
    });

    test('fails when a component-local manifest is malformed', () async {
      _writeComponentsJson(
        registryRoot,
        component: _componentJson(
          id: 'button',
          name: 'Button From Components Json',
          category: 'control',
          shared: const [],
          dependencies: const {},
        ),
      );
      final metaDir = Directory(
          p.join(registryRoot.path, 'components', 'control', 'button'))
        ..createSync(recursive: true);
      File(p.join(metaDir.path, 'meta.json')).writeAsStringSync(
        jsonEncode({'id': 'button'}),
      );

      final registry = await _loadRegistry(registryRoot);
      final resolver = ComponentManifestResolver(registry: registry);

      await expectLater(
        () => resolver.resolve('button'),
        throwsA(isA<ManifestMalformedException>()),
      );
    });
  });
}

Future<Registry> _loadRegistry(Directory registryRoot) {
  return Registry.load(
    registryRoot: RegistryLocation.local(registryRoot.path),
    sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
    skipIntegrity: true,
  );
}

void _writeComponentsJson(
  Directory registryRoot, {
  required Map<String, dynamic> component,
}) {
  File(p.join(registryRoot.path, 'components.json')).writeAsStringSync(
    jsonEncode({
      'schemaVersion': 1,
      'name': 'test',
      'defaults': {
        'installPath': 'lib/ui/shadcn',
        'sharedPath': 'lib/ui/shadcn/shared',
      },
      'shared': [],
      'components': [component],
    }),
  );
}

Map<String, dynamic> _componentJson({
  required String id,
  required String name,
  required String category,
  required List<String> shared,
  required Map<String, String> dependencies,
}) {
  return {
    'id': id,
    'name': name,
    'category': category,
    'files': [
      {
        'source': 'registry/components/$category/$id/$id.dart',
        'destination': '{installPath}/components/$category/$id/$id.dart',
      }
    ],
    'shared': shared,
    'dependsOn': [],
    'pubspec': {'dependencies': dependencies},
    'assets': [],
    'fonts': [],
    'postInstall': [],
  };
}
