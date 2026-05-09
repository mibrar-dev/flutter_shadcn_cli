import 'dart:io';

import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/registry_selection.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/runtime_roots.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('registry selection', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('registry_selection_');
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('accepts v1 registry roots with manifests components json', () {
      final registryRoot = Directory(p.join(tempRoot.path, 'registry'))
        ..createSync(recursive: true);
      File(p.join(registryRoot.path, 'manifests', 'components.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');

      expect(validateRegistryRoot(registryRoot.path), registryRoot.path);
    });

    test('explicit registry path overrides persisted remote mode', () {
      final registryRoot = Directory(p.join(tempRoot.path, 'registry'))
        ..createSync(recursive: true);
      File(p.join(registryRoot.path, 'manifests', 'components.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');

      final args = buildCliParser().parse(
        normalizeCliArgs([
          '--advanced',
          '--registry-path',
          registryRoot.path,
          'validate',
        ]),
      );
      final selection = resolveRegistrySelection(
        args,
        const ResolvedRoots(localRegistryRoot: null, cliRoot: null),
        const ShadcnConfig(
          defaultNamespace: 'shadcn',
          registries: {
            'shadcn': RegistryConfigEntry(
              registryMode: 'remote',
              baseUrl: 'https://example.com/registry',
              componentsPath: 'manifests/components.json',
            ),
          },
        ),
        false,
      );

      expect(selection.mode, 'local');
      expect(selection.registryRoot.isRemote, isFalse);
      expect(selection.registryRoot.root, registryRoot.path);
      expect(selection.componentsPath, 'manifests/components.json');
    });
  });
}
