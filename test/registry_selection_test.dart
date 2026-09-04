import 'dart:io';

import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/registry_bootstrap_exception.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/registry_selection.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/runtime_roots.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry_directory/registry_directory_client.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('default remote registry base points at the live registry repo', () {
    expect(
      resolveRemoteBase(null),
      'https://cdn.jsdelivr.net/gh/mibrar-dev/shadcn_flutter_kit@latest/flutter_shadcn_kit/lib',
    );
  });

  test('default registries directory is served from the live registry repo',
      () {
    expect(
      defaultRegistriesDirectoryUrl,
      'https://flutter-shadcn.github.io/registry-directory/registries/registries.json',
    );
  });

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

    test('missing registry namespace throws bootstrap exception', () {
      final args = buildCliParser().parse(
        normalizeCliArgs([
          '--registry-name',
          'missing',
          'list',
        ]),
      );

      expect(
        () => resolveRegistrySelection(
          args,
          const ResolvedRoots(localRegistryRoot: null, cliRoot: null),
          const ShadcnConfig(
            defaultNamespace: 'shadcn',
            registries: {
              'shadcn': RegistryConfigEntry(baseUrl: 'https://example.com'),
            },
          ),
          false,
        ),
        throwsA(
          isA<RegistryBootstrapException>()
              .having((error) => error.exitCode(), 'exitCode',
                  ExitCodes.configInvalid)
              .having(
                (error) => error.message,
                'message',
                contains('Registry namespace "missing" not found'),
              ),
        ),
      );
    });

    test('missing explicit local registry throws bootstrap exception', () {
      final missingPath = p.join(tempRoot.path, 'missing-registry');
      final args = buildCliParser().parse(
        normalizeCliArgs([
          '--advanced',
          '--registry-path',
          missingPath,
          'list',
        ]),
      );

      expect(
        () => resolveRegistrySelection(
          args,
          const ResolvedRoots(localRegistryRoot: null, cliRoot: null),
          const ShadcnConfig(defaultNamespace: 'shadcn'),
          false,
        ),
        throwsA(
          isA<RegistryBootstrapException>()
              .having((error) => error.exitCode(), 'exitCode',
                  ExitCodes.registryNotFound)
              .having(
                (error) => error.message,
                'message',
                contains('Local registry not found'),
              ),
        ),
      );
    });
  });
}
