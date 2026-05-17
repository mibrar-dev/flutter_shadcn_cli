import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_shadcn_cli/src/init_action_engine.dart';
import 'package:flutter_shadcn_cli/src/registry_directory.dart';
import 'package:flutter_shadcn_cli/src/resolver_v1.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('InitActionEngine', () {
    late Directory tempRoot;
    late Directory projectRoot;
    late HttpServer server;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('shadcn_init_engine_');
      projectRoot = Directory(p.join(tempRoot.path, 'app'))..createSync();
      File(p.join(projectRoot.path, 'pubspec.yaml')).writeAsStringSync(
        [
          'name: test_app',
          'description: test',
          'dependencies:',
          '  flutter:',
          '    sdk: flutter',
        ].join('\n'),
      );

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final path = request.uri.path;
        if (path == '/registry/shared/theme/color_scheme.dart') {
          request.response.statusCode = 200;
          request.response.write('class AppColorScheme {}');
          await request.response.close();
          return;
        }
        if (path == '/registry/shared/fonts/bootstrap.otf') {
          request.response.statusCode = 200;
          request.response.write('font-bytes');
          await request.response.close();
          return;
        }
        if (path == '/registry/components/index.json') {
          request.response.statusCode = 200;
          request.response.write(
            jsonEncode({
              'files': ['registry/components/button/button.dart']
            }),
          );
          await request.response.close();
          return;
        }
        if (path == '/registry/components/button/button.dart') {
          request.response.statusCode = 200;
          request.response.write('class Button {}');
          await request.response.close();
          return;
        }
        request.response.statusCode = 404;
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('executes inline init actions happy path', () async {
      final entry = await _loadFixtureEntry(
        baseUrl: 'http://${server.address.host}:${server.port}/',
      );
      final engine = InitActionEngine();
      final result = await engine.executeRegistryInit(
        projectRoot: projectRoot.path,
        registry: entry,
      );

      expect(result.dirsCreated, greaterThanOrEqualTo(2));
      expect(result.filesWritten, 2);
      expect(result.messages, contains('Init done'));
      expect(
        File(
          p.join(
            projectRoot.path,
            'lib/ui/shadcn/shared/theme/color_scheme.dart',
          ),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(
            projectRoot.path,
            'lib/ui/shadcn/components/button/button.dart',
          ),
        ).existsSync(),
        isTrue,
      );

      final pubspec =
          File(p.join(projectRoot.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec.contains('gap: ^3.0.1'), isTrue);
      expect(pubspec.contains('dev_dependencies:'), isTrue);
      expect(pubspec.contains('lints: ^6.1.0'), isTrue);
      expect(pubspec.contains('assets/fonts/GeistSans-Regular.ttf'), isTrue);
      expect(pubspec.contains('family: GeistSans'), isTrue);

      final doc = loadYaml(pubspec) as YamlMap;
      final flutterSection = doc['flutter'] as YamlMap;
      final dependencies = doc['dependencies'] as YamlMap;
      expect(flutterSection['assets'], isA<YamlList>());
      expect(flutterSection['fonts'], isA<YamlList>());
      expect(dependencies['assets'], isNull);
      expect(dependencies['fonts'], isNull);
    });

    test('mergePubspec writes sdk dependencies as nested yaml maps', () async {
      final engine = InitActionEngine();

      await engine.executeActions(
        projectRoot: projectRoot.path,
        baseUrl: 'http://${server.address.host}:${server.port}/',
        actions: [
          {
            'type': 'mergePubspec',
            'dependencies': {'flutter_localizations': 'sdk: flutter'},
          }
        ],
      );

      final pubspec =
          File(p.join(projectRoot.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('flutter_localizations:'));
      expect(pubspec, contains('  sdk: flutter'));
      expect(pubspec, isNot(contains("flutter_localizations: 'sdk: flutter'")));

      final doc = loadYaml(pubspec) as YamlMap;
      final dependencies = doc['dependencies'] as YamlMap;
      final localizations = dependencies['flutter_localizations'] as YamlMap;
      expect(localizations['sdk'], 'flutter');
    });

    test('mergePubspec fails on conflicting dependency constraint', () async {
      File(p.join(projectRoot.path, 'pubspec.yaml')).writeAsStringSync(
        [
          'name: test_app',
          'dependencies:',
          '  intl: ^0.19.0',
        ].join('\n'),
      );
      final engine = InitActionEngine();

      await expectLater(
        engine.executeActions(
          projectRoot: projectRoot.path,
          baseUrl: 'http://${server.address.host}:${server.port}/',
          actions: [
            {
              'type': 'mergePubspec',
              'dependencies': {'intl': '^0.20.0'},
            }
          ],
        ),
        throwsA(
          predicate(
            (Object error) =>
                error.toString().contains('pubspec.yaml dependency conflict') &&
                error.toString().contains('intl'),
          ),
        ),
      );

      final pubspec =
          File(p.join(projectRoot.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('intl: ^0.19.0'));
      expect(pubspec, isNot(contains('intl: ^0.20.0')));
    });

    test(
        'mergePubspec rejects same package in dependencies and devDependencies',
        () async {
      final engine = InitActionEngine();

      await expectLater(
        engine.executeActions(
          projectRoot: projectRoot.path,
          baseUrl: 'http://${server.address.host}:${server.port}/',
          actions: [
            {
              'type': 'mergePubspec',
              'dependencies': {'foo': '^1.0.0'},
              'devDependencies': {'foo': '^1.0.0'},
            }
          ],
        ),
        throwsA(
          predicate(
            (Object error) =>
                error.toString().contains('pubspec.yaml dependency conflict') &&
                error.toString().contains('foo'),
          ),
        ),
      );

      final pubspec =
          File(p.join(projectRoot.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, isNot(contains('foo: ^1.0.0')));
    });

    test('rolls back recorded inline changes', () async {
      final entry = await _loadFixtureEntry(
        baseUrl: 'http://${server.address.host}:${server.port}/',
      );
      final engine = InitActionEngine();
      final result = await engine.executeRegistryInit(
        projectRoot: projectRoot.path,
        registry: entry,
      );

      final rollback = await engine.rollbackRecordedChanges(
        projectRoot: projectRoot.path,
        record: result.record,
      );

      expect(rollback.filesRemoved, greaterThanOrEqualTo(2));
      expect(
        File(
          p.join(
            projectRoot.path,
            'lib/ui/shadcn/shared/theme/color_scheme.dart',
          ),
        ).existsSync(),
        isFalse,
      );
      final pubspec =
          File(p.join(projectRoot.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec.contains('gap: ^3.0.1'), isFalse);
      expect(pubspec.contains('lints: ^6.1.0'), isFalse);
      expect(pubspec.contains('family: GeistSans'), isFalse);
    });

    test('copyDir requires exactly one of files or index', () async {
      final entry = await _loadFixtureEntry(
        baseUrl: 'http://${server.address.host}:${server.port}/',
        actions: [
          {
            'type': 'copyDir',
            'base': 'registry',
            'destBase': 'lib/ui/shadcn',
            'from': 'components',
            'to': 'components',
            'files': ['registry/components/button/button.dart'],
            'index': 'registry/components/index.json',
          }
        ],
      );
      final engine = InitActionEngine();

      await expectLater(
        () => engine.executeRegistryInit(
          projectRoot: projectRoot.path,
          registry: entry,
        ),
        throwsA(isA<InitActionEngineException>()),
      );
    });

    test('copyFiles from/to accepts files relative to base', () async {
      final entry = await _loadFixtureEntry(
        baseUrl: 'http://${server.address.host}:${server.port}/',
        actions: [
          {
            'type': 'copyFiles',
            'from': 'shared/fonts',
            'to': 'assets/fonts',
            'base': 'registry',
            'destBase': '.',
            'files': ['shared/fonts/bootstrap.otf'],
          }
        ],
      );
      final engine = InitActionEngine();

      await engine.executeRegistryInit(
        projectRoot: projectRoot.path,
        registry: entry,
      );

      final font = File(p.join(projectRoot.path, 'assets/fonts/bootstrap.otf'));
      expect(font.readAsStringSync(), 'font-bytes');
    });

    test('rejects path traversal attempts on destination writes', () async {
      final entry = await _loadFixtureEntry(
        baseUrl: 'http://${server.address.host}:${server.port}/',
        actions: [
          {
            'type': 'copyFiles',
            'base': 'registry',
            'destBase': '../escape',
            'files': ['registry/shared/theme/color_scheme.dart'],
          }
        ],
      );
      final engine = InitActionEngine();

      await expectLater(
        () => engine.executeRegistryInit(
          projectRoot: projectRoot.path,
          registry: entry,
        ),
        throwsA(isA<InitActionEngineException>()),
      );
    });

    test('rejects symlink escape on destination writes', () async {
      final outside = Directory(p.join(tempRoot.path, 'outside'))..createSync();
      Directory(p.join(projectRoot.path, 'lib')).createSync();
      Link(p.join(projectRoot.path, 'lib', 'ui')).createSync(outside.path);
      final entry = await _loadFixtureEntry(
        baseUrl: 'http://${server.address.host}:${server.port}/',
        actions: [
          {
            'type': 'copyFiles',
            'base': 'registry',
            'destBase': 'lib/ui/shadcn',
            'files': ['registry/shared/theme/color_scheme.dart'],
          }
        ],
      );
      final engine = InitActionEngine();

      await expectLater(
        () => engine.executeRegistryInit(
          projectRoot: projectRoot.path,
          registry: entry,
        ),
        throwsA(isA<ResolverV1Exception>()),
      );
      expect(
        File(p.join(outside.path, 'shadcn/theme/color_scheme.dart'))
            .existsSync(),
        isFalse,
      );
    });

    test(
        'supports optional actions, grouped copyFiles, and derived flutter assets from written files',
        () async {
      final engine = InitActionEngine();
      final prompts = <String>[];
      var groupPrompted = false;

      final result = await engine.executeActions(
        projectRoot: projectRoot.path,
        baseUrl: 'http://${server.address.host}:${server.port}/',
        actions: [
          {
            'type': 'ensureDirs',
            'dirs': ['lib/ui/shadcn'],
          },
          {
            'type': 'ensureDirs',
            'optional': true,
            'promptLabel': 'Create optional assets dir?',
            'promptDescription': 'Only needed for add-on assets.',
            'dirs': ['assets/optional'],
          },
          {
            'type': 'copyFiles',
            'optional': true,
            'promptLabel': 'Install shared assets?',
            'promptDescription': 'Pick the shared groups to install.',
            'base': 'registry',
            'destBase': '.',
            'from': 'shared',
            'to': 'assets',
            'groups': [
              {
                'label': 'Fonts',
                'description': 'Font assets',
                'default': true,
                'files': ['fonts/bootstrap.otf'],
              },
              {
                'label': 'Helpers',
                'description': 'Source helpers',
                'default': false,
                'files': ['theme/color_scheme.dart'],
              },
            ],
          },
          {
            'type': 'mergePubspec',
            'deriveFlutterAssets': true,
          },
        ],
        optionalActionDecider: (action) async {
          prompts.add(
            '${action['promptLabel']}|${action['promptDescription'] ?? ''}',
          );
          return false;
        },
        groupSelector: (action, groups) async {
          groupPrompted = true;
          expect(action['promptLabel'], 'Install shared assets?');
          return groups
              .where((group) => group['label'] == 'Fonts')
              .toList(growable: false);
        },
      );

      expect(
        prompts,
        ['Create optional assets dir?|Only needed for add-on assets.'],
      );
      expect(groupPrompted, isTrue);
      expect(
        Directory(p.join(projectRoot.path, 'assets', 'optional')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(projectRoot.path, 'assets', 'fonts', 'bootstrap.otf'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(projectRoot.path, 'assets', 'theme', 'color_scheme.dart'))
            .existsSync(),
        isFalse,
      );
      final pubspec =
          File(p.join(projectRoot.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec.contains('assets/fonts/bootstrap.otf'), isTrue);
      expect(pubspec.contains('assets/theme/color_scheme.dart'), isFalse);
      expect(result.filesWritten, 1);
      expect(result.record.filesWritten, ['assets/fonts/bootstrap.otf']);
      expect(result.record.pubspecDelta.flutterAssets,
          ['assets/fonts/bootstrap.otf']);
    });

    test('inline init rejects code writes outside lib but allows assets',
        () async {
      final engine = InitActionEngine();

      await expectLater(
        engine.executeActions(
          projectRoot: projectRoot.path,
          baseUrl: 'http://${server.address.host}:${server.port}/',
          actions: [
            {
              'type': 'copyFiles',
              'base': 'registry/shared',
              'destBase': '.',
              'files': ['theme/color_scheme.dart'],
            }
          ],
        ),
        throwsA(isA<InitActionEngineException>()),
      );

      final result = await engine.executeActions(
        projectRoot: projectRoot.path,
        baseUrl: 'http://${server.address.host}:${server.port}/',
        actions: [
          {
            'type': 'copyFiles',
            'base': 'registry',
            'destBase': '.',
            'from': 'shared/fonts',
            'to': 'assets/fonts',
            'files': ['shared/fonts/lucide.ttf'],
          },
        ],
      );

      expect(result.filesWritten, 1);
      expect(
        File(p.join(projectRoot.path, 'assets/fonts/lucide.ttf')).existsSync(),
        isTrue,
      );
    });

    test('inline init rejects ensureDirs outside lib or assets', () async {
      final engine = InitActionEngine();

      await expectLater(
        engine.executeActions(
          projectRoot: projectRoot.path,
          baseUrl: 'http://${server.address.host}:${server.port}/',
          actions: [
            {
              'type': 'ensureDirs',
              'dirs': ['shared'],
            }
          ],
        ),
        throwsA(isA<InitActionEngineException>()),
      );
    });

    test('inline init rejects traversal escape even with valid prefix',
        () async {
      final engine = InitActionEngine();

      await expectLater(
        engine.executeActions(
          projectRoot: projectRoot.path,
          baseUrl: 'http://${server.address.host}:${server.port}/',
          actions: [
            {
              'type': 'copyFiles',
              'base': 'registry',
              'destBase': 'lib/../escape',
              'files': ['registry/shared/theme/color_scheme.dart'],
            }
          ],
        ),
        throwsA(isA<ResolverV1Exception>()),
      );
    });
  });
}

Future<RegistryDirectoryEntry> _loadFixtureEntry({
  required String baseUrl,
  List<dynamic>? actions,
}) async {
  final packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_shadcn_cli/flutter_shadcn_cli.dart'),
  );
  if (packageUri == null) {
    throw Exception('Could not resolve package root');
  }
  final packageRoot = p.dirname(p.dirname(File.fromUri(packageUri).path));
  final raw = jsonDecode(
    File(
      p.join(
        packageRoot,
        'test',
        'fixtures',
        'registry_inline_init_entry.json',
      ),
    ).readAsStringSync(),
  ) as Map<String, dynamic>;
  raw['baseUrl'] = baseUrl;
  if (actions != null) {
    (raw['init'] as Map<String, dynamic>)['actions'] = actions;
  }
  return RegistryDirectoryEntry.fromJson(raw);
}
