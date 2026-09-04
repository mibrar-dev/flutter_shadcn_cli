import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:flutter_shadcn_cli/src/validate_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('runValidateCommand', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('validate_command_');
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('uses the schema path captured by registry selection', () async {
      final registryRoot = Directory(p.join(tempRoot.path, 'registry'))
        ..createSync(recursive: true);
      File(p.join(registryRoot.path, 'manifests', 'components.schema.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            r'$schema': 'https://json-schema.org/draft/2020-12/schema',
            'type': 'object',
            'required': ['schemaVersion', 'name', 'defaults'],
            'properties': {
              'schemaVersion': {'type': 'integer'},
              'name': {'type': 'string'},
              'defaults': {'type': 'object'},
              'shared': {'type': 'array'},
              'components': {'type': 'array'},
            },
          }),
        );

      final registry = Registry(
        {
          r'$schema': './components.schema.json',
          'schemaVersion': 1,
          'name': 'fixture_registry',
          'defaults': {},
          'shared': const [],
          'components': const [],
        },
        RegistryLocation.local(registryRoot.path),
        RegistryLocation.local(registryRoot.path),
        'manifests/components.schema.json',
      );

      final exitCode = await runValidateCommand(
        registry: registry,
        registryRoot: registry.registryRoot,
        sourceRoot: registry.sourceRoot,
        offline: false,
        jsonOutput: false,
        logger: CliLogger(useColor: false),
      );

      expect(exitCode, 0);
    });
  });
}
