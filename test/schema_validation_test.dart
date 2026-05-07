import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:flutter_shadcn_cli/src/registry_directory.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_source.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  Future<Directory> createSchemaFixtureDir() async {
    final dir =
        await Directory.systemTemp.createTemp('schema_validation_test_');
    final schemaFile = File(p.join(dir.path, 'components.schema.json'));
    final componentsFile = File(p.join(dir.path, 'components.json'));

    await schemaFile.writeAsString(
      jsonEncode({
        r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        'type': 'object',
        'required': ['schemaVersion', 'name', 'defaults'],
        'properties': {
          'schemaVersion': {'type': 'integer'},
          'name': {'type': 'string'},
          'defaults': {'type': 'object'},
        },
      }),
    );

    await componentsFile.writeAsString(
      jsonEncode({
        r'$schema': './components.schema.json',
        'schemaVersion': 1,
        'name': 'fixture_registry',
        'defaults': {'installPath': 'lib/ui/shadcn'},
      }),
    );

    return dir;
  }

  test('components.json validates against schema', () async {
    final fixtureDir = await createSchemaFixtureDir();
    addTearDown(() => fixtureDir.delete(recursive: true));

    final registryRoot = RegistryLocation.local(fixtureDir.path);
    final content = await registryRoot.readString('components.json');
    final data = jsonDecode(content);
    expect(data, isA<Map<String, dynamic>>());

    final schemaSource = ComponentsSchemaValidator.resolveSchemaSource(
      data: data as Map<String, dynamic>,
      registryRoot: registryRoot,
    );
    expect(schemaSource, isNotNull);

    final result = await ComponentsSchemaValidator.validateWithJsonSchema(
      data,
      schemaSource!,
    );
    expect(
      result.isValid,
      isTrue,
      reason: result.errors.take(5).join('\n'),
    );
  });

  test('invalid fixture fails schema validation', () async {
    final fixtureDir = await createSchemaFixtureDir();
    addTearDown(() => fixtureDir.delete(recursive: true));

    final registryRoot = RegistryLocation.local(fixtureDir.path);
    final schemaSource = ComponentsSchemaValidator.resolveSchemaSource(
      data: const {},
      registryRoot: registryRoot,
    );
    expect(schemaSource, isNotNull);

    final invalid = {
      'schemaVersion': '1',
      'name': 'invalid_registry',
      'defaults': {},
    };

    final result = await ComponentsSchemaValidator.validateWithJsonSchema(
      invalid,
      schemaSource!,
    );
    expect(result.isValid, isFalse);
  });

  test('Registry.fromContent rejects invalid explicit schema by default',
      () async {
    final fixtureDir = await createSchemaFixtureDir();
    addTearDown(() => fixtureDir.delete(recursive: true));

    final registryRoot = RegistryLocation.local(fixtureDir.path);
    final invalid = jsonEncode({
      r'$schema': './components.schema.json',
      'schemaVersion': '1',
      'name': 'invalid_registry',
      'defaults': {},
    });

    expect(
      () => Registry.fromContent(
        content: invalid,
        registryRoot: registryRoot,
        sourceRoot: registryRoot,
      ),
      throwsA(isA<RegistrySchemaValidationException>()),
    );
  });

  test('Registry.fromContent rejects unsupported component schemaVersion',
      () async {
    final fixtureDir = await createSchemaFixtureDir();
    addTearDown(() => fixtureDir.delete(recursive: true));

    final registryRoot = RegistryLocation.local(fixtureDir.path);
    final content = jsonEncode({
      'schemaVersion': 2,
      'name': 'future_registry',
      'defaults': {},
      'components': [],
    });

    await expectLater(
      () => Registry.fromContent(
        content: content,
        registryRoot: registryRoot,
        sourceRoot: registryRoot,
        skipIntegrity: true,
      ),
      throwsA(
        isA<RegistrySchemaValidationException>().having(
          (error) => error.errors.join('\n'),
          'errors',
          allOf(
            contains('schemaVersion'),
            contains('1'),
            contains('2'),
          ),
        ),
      ),
    );
  });

  test('Registry.fromContent reports malformed JSON as validation error',
      () async {
    final registryRoot = RegistryLocation.local('/tmp/registry');

    await expectLater(
      () => Registry.fromContent(
        content: '{not-json',
        registryRoot: registryRoot,
        sourceRoot: registryRoot,
      ),
      throwsA(
        isA<RegistrySchemaValidationException>().having(
          (error) => error.toString(),
          'message',
          contains('components.json is not valid JSON'),
        ),
      ),
    );
  });

  test('Registry.load validates before writing remote cache', () async {
    final fixtureDir = await createSchemaFixtureDir();
    addTearDown(() => fixtureDir.delete(recursive: true));

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });
    server.listen((request) async {
      if (request.uri.path == '/registry/components.json') {
        request.response.statusCode = 200;
        request.response.write(jsonEncode({
          r'$schema': './components.schema.json',
          'schemaVersion': '1',
          'name': 'invalid_registry',
          'defaults': {},
        }));
      } else if (request.uri.path == '/registry/components.schema.json') {
        request.response.statusCode = 200;
        request.response.write(
          await File(p.join(fixtureDir.path, 'components.schema.json'))
              .readAsString(),
        );
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });

    final cacheFile = File(p.join(fixtureDir.path, 'cache', 'components.json'));
    await expectLater(
      () => Registry.load(
        registryRoot: RegistryLocation.remote(
          'http://${server.address.host}:${server.port}/registry',
        ),
        sourceRoot: RegistryLocation.remote(
          'http://${server.address.host}:${server.port}/registry',
        ),
        cachePath: cacheFile.path,
      ),
      throwsA(isA<RegistrySchemaValidationException>()),
    );

    expect(cacheFile.existsSync(), isFalse);
  });

  test('directory registry source validates before writing components cache',
      () async {
    final fixtureDir = await createSchemaFixtureDir();
    addTearDown(() => fixtureDir.delete(recursive: true));

    final projectRoot = await Directory.systemTemp.createTemp(
      'schema_validation_project_',
    );
    addTearDown(() => projectRoot.delete(recursive: true));

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });
    server.listen((request) async {
      if (request.uri.path == '/registry/components.json') {
        request.response.statusCode = 200;
        request.response.write(jsonEncode({
          r'$schema': './components.schema.json',
          'schemaVersion': '1',
          'name': 'invalid_registry',
          'defaults': {},
        }));
      } else if (request.uri.path == '/registry/components.schema.json') {
        request.response.statusCode = 200;
        request.response.write(
          await File(p.join(fixtureDir.path, 'components.schema.json'))
              .readAsString(),
        );
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });

    final source = RegistrySource.fromDirectory(
      RegistryDirectoryEntry(
        id: 'invalid',
        displayName: 'Invalid',
        minCliVersion: '0.1.0',
        baseUrl: 'http://${server.address.host}:${server.port}/registry',
        namespace: 'invalid',
        installRoot: 'lib/ui/invalid',
        paths: const {
          'componentsJson': 'components.json',
          'componentsSchemaJson': 'components.schema.json',
        },
        capabilities: const RegistryCapabilities(),
        trust: const RegistryTrust(),
        init: null,
        raw: const {},
      ),
    );

    await expectLater(
      () => source.loadRegistry(
        projectRoot: projectRoot.path,
        offline: false,
        skipIntegrity: false,
        logger: CliLogger(),
        directoryClient: RegistryDirectoryClient(),
      ),
      throwsA(isA<RegistrySchemaValidationException>()),
    );

    expect(
      File(
        p.join(
          projectRoot.path,
          '.shadcn',
          'cache',
          'components_invalid.json',
        ),
      ).existsSync(),
      isFalse,
    );
  });

  test(
      'directory registry source does not use stale cache on invalid fresh body',
      () async {
    final fixtureDir = await createSchemaFixtureDir();
    addTearDown(() => fixtureDir.delete(recursive: true));

    final projectRoot = await Directory.systemTemp.createTemp(
      'schema_validation_project_stale_',
    );
    addTearDown(() => projectRoot.delete(recursive: true));

    var invalid = false;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });
    server.listen((request) async {
      if (request.uri.path == '/registry/components.json') {
        request.response.statusCode = 200;
        request.response.write(jsonEncode({
          r'$schema': './components.schema.json',
          'schemaVersion': invalid ? '1' : 1,
          'name': invalid ? 'invalid_registry' : 'valid_registry',
          'defaults': {},
        }));
      } else if (request.uri.path == '/registry/components.schema.json') {
        request.response.statusCode = 200;
        request.response.write(
          await File(p.join(fixtureDir.path, 'components.schema.json'))
              .readAsString(),
        );
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });

    final source = RegistrySource.fromDirectory(
      RegistryDirectoryEntry(
        id: 'stale',
        displayName: 'Stale',
        minCliVersion: '0.1.0',
        baseUrl: 'http://${server.address.host}:${server.port}/registry',
        namespace: 'stale',
        installRoot: 'lib/ui/stale',
        paths: const {
          'componentsJson': 'components.json',
          'componentsSchemaJson': 'components.schema.json',
        },
        capabilities: const RegistryCapabilities(),
        trust: const RegistryTrust(),
        init: null,
        raw: const {},
      ),
    );
    final client = RegistryDirectoryClient();
    final first = await source.loadRegistry(
      projectRoot: projectRoot.path,
      offline: false,
      skipIntegrity: false,
      logger: CliLogger(),
      directoryClient: client,
    );
    expect(first.data['name'], 'valid_registry');

    invalid = true;
    await expectLater(
      () => source.loadRegistry(
        projectRoot: projectRoot.path,
        offline: false,
        skipIntegrity: false,
        logger: CliLogger(),
        directoryClient: client,
      ),
      throwsA(isA<RegistrySchemaValidationException>()),
    );
  });

  test('Registry.fromContent rejects missing explicit schema by default',
      () async {
    final fixtureDir = await Directory.systemTemp.createTemp(
      'schema_validation_missing_schema_test_',
    );
    addTearDown(() => fixtureDir.delete(recursive: true));

    final registryRoot = RegistryLocation.local(fixtureDir.path);
    final content = jsonEncode({
      'schemaVersion': 1,
      'name': 'missing_schema_registry',
      'defaults': {},
    });

    expect(
      () => Registry.fromContent(
        content: content,
        registryRoot: registryRoot,
        sourceRoot: registryRoot,
        schemaPath: 'components.schema.json',
      ),
      throwsA(isA<RegistrySchemaValidationException>()),
    );
  });

  test('Registry.fromContent rejects missing implicit schema by default',
      () async {
    final fixtureDir = await Directory.systemTemp.createTemp(
      'schema_validation_implicit_missing_schema_test_',
    );
    addTearDown(() => fixtureDir.delete(recursive: true));

    final registryRoot = RegistryLocation.local(fixtureDir.path);
    final content = jsonEncode({
      'schemaVersion': 1,
      'name': 'missing_implicit_schema_registry',
      'defaults': {},
    });

    expect(
      () => Registry.fromContent(
        content: content,
        registryRoot: registryRoot,
        sourceRoot: registryRoot,
      ),
      throwsA(isA<RegistrySchemaValidationException>()),
    );
  });

  test('Registry caches parsed components per instance', () async {
    final registryRoot = RegistryLocation.local('/tmp/registry');
    final registry = await Registry.fromContent(
      content: jsonEncode({
        'schemaVersion': 1,
        'name': 'component_cache_registry',
        'defaults': {},
        'components': [
          {
            'id': 'PrimaryButton',
            'name': 'Button',
            'files': [],
          }
        ],
      }),
      registryRoot: registryRoot,
      sourceRoot: registryRoot,
      skipIntegrity: true,
    );

    expect(identical(registry.components, registry.components), isTrue);
    expect(
      registry.getComponent('primarybutton'),
      same(registry.getComponent('PrimaryButton')),
    );
    expect(
      registry.getComponent('button'),
      same(registry.getComponent('Button')),
    );
  });

  test('schema validator caches compiled validators by schema source',
      () async {
    var reads = 0;
    final schemaSource = SchemaSource(
      label: 'memory://components.schema.json',
      read: () async {
        reads += 1;
        return jsonEncode({
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          'type': 'object',
          'required': ['name'],
          'properties': {
            'name': {'type': 'string'},
          },
        });
      },
    );

    final first = await ComponentsSchemaValidator.validateWithJsonSchema(
      {'name': 'first'},
      schemaSource,
    );
    final second = await ComponentsSchemaValidator.validateWithJsonSchema(
      {'name': 'second'},
      schemaSource,
    );

    expect(first.isValid, isTrue);
    expect(second.isValid, isTrue);
    expect(reads, 1);
  });

  test('schema validator evicts failed schema reads', () async {
    var reads = 0;
    final schemaSource = SchemaSource(
      label: 'memory://flaky-components.schema.json',
      read: () async {
        reads += 1;
        if (reads == 1) {
          throw Exception('temporary schema read failure');
        }
        return jsonEncode({
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          'type': 'object',
          'required': ['name'],
          'properties': {
            'name': {'type': 'string'},
          },
        });
      },
    );

    final first = await ComponentsSchemaValidator.validateWithJsonSchema(
      {'name': 'first'},
      schemaSource,
    );
    final second = await ComponentsSchemaValidator.validateWithJsonSchema(
      {'name': 'second'},
      schemaSource,
    );

    expect(first.isValid, isFalse);
    expect(second.isValid, isTrue);
    expect(reads, 2);
  });

  test('Registry.fromContent bypasses explicit schema with skipIntegrity',
      () async {
    final fixtureDir = await createSchemaFixtureDir();
    addTearDown(() => fixtureDir.delete(recursive: true));

    final registryRoot = RegistryLocation.local(fixtureDir.path);
    final invalid = jsonEncode({
      r'$schema': './components.schema.json',
      'schemaVersion': 1,
      'name': 'invalid_registry',
    });

    final registry = await Registry.fromContent(
      content: invalid,
      registryRoot: registryRoot,
      sourceRoot: registryRoot,
      skipIntegrity: true,
    );

    expect(registry.data['name'], 'invalid_registry');
  });
}
