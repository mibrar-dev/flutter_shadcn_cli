import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:flutter_shadcn_cli/src/registry_directory.dart';
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

  test('Registry.fromContent bypasses schema validation with skipIntegrity',
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

    final registry = await Registry.fromContent(
      content: invalid,
      registryRoot: registryRoot,
      sourceRoot: registryRoot,
      skipIntegrity: true,
    );

    expect(registry.data['name'], 'invalid_registry');
  });

  test('registries schema rejects unsupported init patch declarations',
      () async {
    for (final unsupportedField in [
      'configPatches',
      'patches',
      'mainDartPatch',
    ]) {
      final fixtureDir = await Directory.systemTemp.createTemp(
        'registries_schema_unsupported_patch_test_',
      );
      addTearDown(() => fixtureDir.delete(recursive: true));
      final registriesFile = File(p.join(fixtureDir.path, 'registries.json'));
      await registriesFile.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'registries': [
            {
              'id': 'patchy',
              'displayName': 'Patchy',
              'maintainers': ['team'],
              'repo': 'https://github.com/example/patchy',
              'license': 'MIT',
              'minCliVersion': '0.1.0',
              'baseUrl': 'https://example.com/registry/',
              'paths': {'componentsJson': 'components.json'},
              'install': {'namespace': 'patchy', 'root': 'lib/ui/patchy'},
              'init': {
                'version': 1,
                'actions': [
                  {
                    'type': 'message',
                    'lines': ['never accepted'],
                    unsupportedField: [
                      {'path': 'lib/main.dart'}
                    ],
                  }
                ],
              },
            }
          ],
        }),
      );

      final client = RegistryDirectoryClient();
      await expectLater(
        () => client.load(
          projectRoot: fixtureDir.path,
          directoryPath: registriesFile.path,
          currentCliVersion: '0.1.8',
        ),
        throwsA(
          predicate(
            (Object error) =>
                error is RegistryDirectoryException &&
                error.toString().contains('registries.json schema invalid'),
          ),
        ),
        reason: unsupportedField,
      );
    }
  });

  test('registries schema rejects unsupported modifyFile init action',
      () async {
    final fixtureDir = await Directory.systemTemp.createTemp(
      'registries_schema_unsupported_action_test_',
    );
    addTearDown(() => fixtureDir.delete(recursive: true));
    final registriesFile = File(p.join(fixtureDir.path, 'registries.json'));
    await registriesFile.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'registries': [
          {
            'id': 'patchy',
            'displayName': 'Patchy',
            'maintainers': ['team'],
            'repo': 'https://github.com/example/patchy',
            'license': 'MIT',
            'minCliVersion': '0.1.0',
            'baseUrl': 'https://example.com/registry/',
            'paths': {'componentsJson': 'components.json'},
            'install': {'namespace': 'patchy', 'root': 'lib/ui/patchy'},
            'init': {
              'version': 1,
              'actions': [
                {
                  'type': 'modifyFile',
                  'path': 'lib/main.dart',
                }
              ],
            },
          }
        ],
      }),
    );

    final client = RegistryDirectoryClient();
    await expectLater(
      () => client.load(
        projectRoot: fixtureDir.path,
        directoryPath: registriesFile.path,
        currentCliVersion: '0.1.8',
      ),
      throwsA(
        predicate(
          (Object error) =>
              error is RegistryDirectoryException &&
              error.toString().contains('registries.json schema invalid'),
        ),
      ),
    );
  });
}
