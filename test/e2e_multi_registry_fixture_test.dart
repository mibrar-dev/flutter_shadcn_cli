import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/multi_registry_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('E2E fixtures', () {
    late Directory tempRoot;
    late Directory appRoot;
    late Directory registryBase;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('shadcn_e2e_fixture_');
      appRoot = Directory(p.join(tempRoot.path, 'app'))..createSync();
      registryBase = Directory(p.join(tempRoot.path, 'registry_base'))
        ..createSync();
      _writeMinimalRegistry(registryBase);
      File(p.join(appRoot.path, 'pubspec.yaml')).writeAsStringSync(
        [
          'name: fixture_app',
          'dependencies:',
          '  flutter:',
          '    sdk: flutter',
        ].join('\n'),
      );
      Directory(p.join(appRoot.path, '.shadcn')).createSync(recursive: true);
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('older-shaped config/state fixture supports add shadcn:button',
        () async {
      final packageRoot = await _packageRoot();
      final oldConfig = jsonDecode(
        File(p.join(packageRoot, 'test', 'fixtures', 'old_config.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      oldConfig['registryMode'] = 'local';
      oldConfig['registryPath'] = p.join(registryBase.path, 'registry');
      File(p.join(appRoot.path, '.shadcn', 'config.json'))
          .writeAsStringSync(jsonEncode(oldConfig));
      File(p.join(appRoot.path, '.shadcn', 'state.json')).writeAsStringSync(
        File(p.join(packageRoot, 'test', 'fixtures', 'old_state.json'))
            .readAsStringSync(),
      );

      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: true,
        logger: CliLogger(),
      );
      await manager.runAdd(['shadcn:button']);

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
      final normalizedState = jsonDecode(
        File(p.join(appRoot.path, '.shadcn', 'state.json')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(normalizedState['registries'], isA<Map>());
      expect(normalizedState['managedDependencies'], isA<List>());
    });

    test('init shadcn executes inline init fixture actions', () async {
      final packageRoot = await _packageRoot();
      final fixture = jsonDecode(
        File(
          p.join(
            packageRoot,
            'test',
            'fixtures',
            'registry_inline_init_entry.json',
          ),
        ).readAsStringSync(),
      ) as Map<String, dynamic>;
      final registryEntry = Map<String, dynamic>.from(fixture);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      server.listen((request) async {
        final path = request.uri.path;
        if (path == '/registries.json') {
          final entry = Map<String, dynamic>.from(registryEntry)
            ..['baseUrl'] = 'https://example.com/registry/'
            ..['paths'] = {
              'componentsJson': 'components.json',
              'componentsSchemaJson': 'components.schema.json',
            };
          request.response.write(
            jsonEncode({
              'schemaVersion': 1,
              'registries': [entry],
            }),
          );
          await request.response.close();
          return;
        }
        if (path == '/registry/shared/theme/color_scheme.dart') {
          request.response.write('class AppColorScheme {}');
          await request.response.close();
          return;
        }
        if (path == '/registry/components/index.json') {
          request.response.write(
            jsonEncode({
              'files': ['registry/components/button/button.dart'],
            }),
          );
          await request.response.close();
          return;
        }
        if (path == '/registry/components/button/button.dart') {
          request.response.write('class Button {}');
          await request.response.close();
          return;
        }
        if (path == '/components.json') {
          request.response.write(
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
          await request.response.close();
          return;
        }
        if (path == '/components.schema.json') {
          request.response.write(jsonEncode({}));
          await request.response.close();
          return;
        }
        request.response.statusCode = 404;
        await request.response.close();
      });

      File(p.join(appRoot.path, '.shadcn', 'config.json')).writeAsStringSync(
        jsonEncode({
          'defaultNamespace': 'shadcn',
          'registries': {
            'shadcn': {
              'registryMode': 'remote',
              'registryUrl': 'http://${server.address.host}:${server.port}/',
              'baseUrl': 'http://${server.address.host}:${server.port}/',
              'installPath': 'lib/ui/shadcn',
              'sharedPath': 'lib/ui/shadcn/shared',
              'enabled': true
            }
          }
        }),
      );

      final manager = MultiRegistryManager(
        targetDir: appRoot.path,
        offline: false,
        logger: CliLogger(),
        directoryUrl:
            'http://${server.address.host}:${server.port}/registries.json',
      );
      await manager.runNamespaceInit('shadcn');

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
      expect(
        File(
          p.join(
            appRoot.path,
            'lib',
            'ui',
            'shadcn',
            'shared',
            'theme',
            'color_scheme.dart',
          ),
        ).existsSync(),
        isTrue,
      );
    });
  });
}

Future<String> _packageRoot() async {
  final packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_shadcn_cli/flutter_shadcn_cli.dart'),
  );
  if (packageUri == null) {
    throw Exception('Could not resolve package root');
  }
  return p.dirname(p.dirname(File.fromUri(packageUri).path));
}

void _writeMinimalRegistry(Directory baseDir) {
  final registryRoot = Directory(p.join(baseDir.path, 'registry'))
    ..createSync(recursive: true);
  final componentDir = Directory(
    p.join(baseDir.path, 'registry', 'components', 'button'),
  )..createSync(recursive: true);
  File(p.join(componentDir.path, 'button.dart'))
      .writeAsStringSync('class Button {}');
  File(p.join(registryRoot.path, 'components.schema.json')).writeAsStringSync(
    jsonEncode({r'$schema': 'https://json-schema.org/draft/2020-12/schema'}),
  );
  File(p.join(registryRoot.path, 'components.json')).writeAsStringSync(
    jsonEncode({
      'schemaVersion': 1,
      'name': 'test_registry',
      'flutter': {'minSdk': '3.0.0'},
      'defaults': {
        'installPath': 'lib/ui/shadcn',
        'sharedPath': 'lib/ui/shadcn/shared',
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
              'destination': '{installPath}/components/button/button.dart',
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
    }),
  );
}
