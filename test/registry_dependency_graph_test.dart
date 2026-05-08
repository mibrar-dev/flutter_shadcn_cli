import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/registry_dependency_graph.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('RegistryDependencyGraph', () {
    late Directory tempRoot;
    late Directory registryRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('shadcn_graph_test_');
      registryRoot = Directory(p.join(tempRoot.path, 'registry'))
        ..createSync(recursive: true);
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('detects component dependency cycles with exact path', () async {
      final registry = await _writeRegistry(
        registryRoot,
        components: [
          _component('button', dependsOn: ['form_control']),
          _component('form_control', dependsOn: ['button']),
        ],
      );

      await expectLater(
        RegistryDependencyGraph(registry).validateComponentInstall(['button']),
        throwsA(
          isA<RegistryDependencyCycleException>().having(
            (error) => error.path,
            'path',
            ['button', 'form_control', 'button'],
          ),
        ),
      );
    });

    test('detects component self cycles', () async {
      final registry = await _writeRegistry(
        registryRoot,
        components: [
          _component('button', dependsOn: ['button']),
        ],
      );

      await expectLater(
        RegistryDependencyGraph(registry).validateComponentInstall(['button']),
        throwsA(
          isA<RegistryDependencyCycleException>().having(
            (error) => error.path,
            'path',
            ['button', 'button'],
          ),
        ),
      );
    });

    test('detects shared dependency cycles from imports', () async {
      _writeSource(
        registryRoot,
        'registry/shared/a/a.dart',
        "import '../b/b.dart';\nclass A {}\n",
      );
      _writeSource(
        registryRoot,
        'registry/shared/b/b.dart',
        "import '../a/a.dart';\nclass B {}\n",
      );
      final registry = await _writeRegistry(
        registryRoot,
        shared: [
          _shared('a', 'registry/shared/a/a.dart'),
          _shared('b', 'registry/shared/b/b.dart'),
        ],
        components: [
          _component('button', shared: ['a']),
        ],
      );

      await expectLater(
        RegistryDependencyGraph(registry).validateComponentInstall(['button']),
        throwsA(
          isA<RegistryDependencyCycleException>().having(
            (error) => error.path,
            'path',
            ['shared:a', 'shared:b', 'shared:a'],
          ),
        ),
      );
    });

    test('detects shared dependency cycles from exports', () async {
      _writeSource(registryRoot, 'registry/shared/a/a.dart',
          "export '../b/b.dart';\nclass A {}\n");
      _writeSource(registryRoot, 'registry/shared/b/b.dart',
          "export '../a/a.dart';\nclass B {}\n");
      final registry = await _writeRegistry(
        registryRoot,
        shared: [
          _shared('a', 'registry/shared/a/a.dart'),
          _shared('b', 'registry/shared/b/b.dart'),
        ],
        components: [
          _component('button', shared: ['a']),
        ],
      );

      await expectLater(
        RegistryDependencyGraph(registry).validateComponentInstall(['button']),
        throwsA(isA<RegistryDependencyCycleException>()),
      );
    });

    test('ignores unrelated file cycles outside requested install graph',
        () async {
      final registry = await _writeRegistry(
        registryRoot,
        components: [
          _component('button'),
          {
            'id': 'broken',
            'name': 'broken',
            'files': [
              {
                'source': 'registry/components/broken/a.dart',
                'destination': '{installPath}/components/broken/a.dart',
                'dependsOn': ['registry/components/broken/b.dart'],
              },
              {
                'source': 'registry/components/broken/b.dart',
                'destination': '{installPath}/components/broken/b.dart',
                'dependsOn': ['registry/components/broken/a.dart'],
              }
            ],
            'shared': [],
            'dependsOn': [],
            'pubspec': {'dependencies': <String, dynamic>{}},
          }
        ],
      );

      await RegistryDependencyGraph(registry).validateComponentInstall([
        'button',
      ]);
    });

    test('does not treat optional file dependencies as hard cycles', () async {
      final registry = await _writeRegistry(
        registryRoot,
        components: [
          _component(
            'button',
            fileDependsOn: [
              {
                'source': 'registry/components/card/card.dart',
                'optional': true,
              },
            ],
          ),
          _component(
            'card',
            fileDependsOn: ['registry/components/button/button.dart'],
          ),
        ],
      );

      await RegistryDependencyGraph(
        registry,
      ).validateComponentInstall(['button']);
    });

    test('detects same-component file dependency cycles', () async {
      final registry = await _writeRegistry(
        registryRoot,
        components: [
          {
            'id': 'button',
            'name': 'button',
            'files': [
              {
                'source': 'registry/components/button/a.dart',
                'destination': '{installPath}/components/button/a.dart',
                'dependsOn': ['registry/components/button/b.dart'],
              },
              {
                'source': 'registry/components/button/b.dart',
                'destination': '{installPath}/components/button/b.dart',
                'dependsOn': ['registry/components/button/a.dart'],
              },
            ],
            'shared': [],
            'dependsOn': [],
            'pubspec': {'dependencies': <String, dynamic>{}},
          },
        ],
      );

      await expectLater(
        RegistryDependencyGraph(registry).validateComponentInstall(['button']),
        throwsA(
          isA<RegistryDependencyCycleException>()
              .having((error) => error.path, 'path', [
            'registry/components/button/a.dart',
            'registry/components/button/b.dart',
            'registry/components/button/a.dart',
          ]),
        ),
      );
    });

    test('reports missing component dependencies separately', () async {
      final registry = await _writeRegistry(
        registryRoot,
        components: [
          _component('button', dependsOn: ['missing']),
        ],
      );

      await expectLater(
        RegistryDependencyGraph(registry).validateComponentInstall(['button']),
        throwsA(isA<RegistryDependencyMissingException>()),
      );
    });

    test('reports missing required file dependencies separately', () async {
      final registry = await _writeRegistry(
        registryRoot,
        components: [
          _component(
            'button',
            fileDependsOn: ['registry/components/missing/missing.dart'],
          ),
        ],
      );

      await expectLater(
        RegistryDependencyGraph(registry).validateComponentInstall(['button']),
        throwsA(isA<RegistryDependencyMissingException>()),
      );
    });
  });
}

Future<Registry> _writeRegistry(
  Directory registryRoot, {
  List<Map<String, dynamic>> shared = const [],
  required List<Map<String, dynamic>> components,
}) async {
  for (final component in components) {
    for (final file in component['files'] as List<dynamic>) {
      final source = (file as Map<String, dynamic>)['source'] as String;
      if (!File(
        p.join(registryRoot.path, p.relative(source, from: 'registry')),
      ).existsSync()) {
        _writeSource(registryRoot, source, 'class ${component['name']} {}\n');
      }
    }
  }
  for (final item in shared) {
    for (final file in item['files'] as List<dynamic>) {
      final source = (file as Map<String, dynamic>)['source'] as String;
      final target = File(
        p.join(registryRoot.path, p.relative(source, from: 'registry')),
      );
      if (!target.existsSync()) {
        _writeSource(registryRoot, source, 'class ${item['id']} {}\n');
      }
    }
  }
  File(p.join(registryRoot.path, 'components.json')).writeAsStringSync(
    jsonEncode({
      'defaults': {
        'installPath': 'lib/ui/shadcn',
        'sharedPath': 'lib/ui/shadcn/shared',
      },
      'shared': shared,
      'components': components,
    }),
  );
  return Registry.load(
    registryRoot: RegistryLocation.local(registryRoot.path),
    sourceRoot: RegistryLocation.local(p.dirname(registryRoot.path)),
    skipIntegrity: true,
  );
}

Map<String, dynamic> _component(
  String id, {
  List<String> dependsOn = const [],
  List<String> shared = const [],
  List<dynamic> fileDependsOn = const [],
}) {
  return {
    'id': id,
    'name': id,
    'files': [
      {
        'source': 'registry/components/$id/$id.dart',
        'destination': '{installPath}/components/$id/$id.dart',
        if (fileDependsOn.isNotEmpty) 'dependsOn': fileDependsOn,
      },
    ],
    'shared': shared,
    'dependsOn': dependsOn,
    'pubspec': {'dependencies': <String, dynamic>{}},
  };
}

Map<String, dynamic> _shared(String id, String source) {
  return {
    'id': id,
    'files': [
      {'source': source, 'destination': '{sharedPath}/$id/$id.dart'},
    ],
  };
}

void _writeSource(Directory registryRoot, String source, String content) {
  final relative = p.relative(source, from: 'registry');
  final file = File(p.join(registryRoot.path, relative));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}
