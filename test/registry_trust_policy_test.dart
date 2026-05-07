import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/registry_source.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry_directory/registry_directory_client.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry_directory/registry_directory_entry.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry_directory/registry_directory_exception.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry_directory/registry_capabilities.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry_directory/registry_trust.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:test/test.dart';

void main() {
  group('registry trust policy', () {
    late Directory tempProject;

    setUp(() {
      tempProject =
          Directory.systemTemp.createTempSync('shadcn_trust_policy_test_');
    });

    tearDown(() {
      if (tempProject.existsSync()) {
        tempProject.deleteSync(recursive: true);
      }
    });

    test('rejects non-HTTPS remote registries directory URL before fetch',
        () async {
      final client = RegistryDirectoryClient();

      await expectLater(
        () => client.load(
          projectRoot: tempProject.path,
          directoryUrl: 'http://example.com/registries.json',
          currentCliVersion: '0.1.8',
        ),
        throwsA(
          isA<RegistryDirectoryException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('registries.json'),
              contains('https'),
              contains('http://example.com/registries.json'),
            ),
          ),
        ),
      );
    });

    test('rejects non-local remote registry without sha256 trust metadata',
        () async {
      final client = RegistryDirectoryClient();
      final entry = RegistryDirectoryEntry(
        id: 'untrusted',
        displayName: 'Untrusted',
        minCliVersion: '0.1.0',
        baseUrl: 'https://example.com/registry/',
        namespace: 'untrusted',
        installRoot: 'lib/ui/untrusted',
        paths: const {'componentsJson': 'components.json'},
        capabilities: const RegistryCapabilities(),
        trust: const RegistryTrust(),
        init: null,
        raw: const {},
      );

      await expectLater(
        () => client.loadComponentsJson(
          projectRoot: tempProject.path,
          registry: entry,
        ),
        throwsA(
          isA<RegistryDirectoryException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('untrusted'),
              contains('trust.mode'),
              contains('sha256'),
            ),
          ),
        ),
      );
    });

    test('rejects config-based remote source without sha256 trust metadata',
        () async {
      final source = RegistrySource.fromConfig(
        namespace: 'remote',
        configEntry: const RegistryConfigEntry(
          registryMode: 'remote',
          baseUrl: 'https://example.com/registry/',
          installPath: 'lib/ui/remote',
          enabled: true,
        ),
      );

      await expectLater(
        () => source.loadRegistry(
          projectRoot: tempProject.path,
          offline: false,
          skipIntegrity: true,
          logger: CliLogger(verbose: false),
          directoryClient: RegistryDirectoryClient(),
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            allOf(
              contains('remote'),
              contains('trustMode'),
              contains('sha256'),
            ),
          ),
        ),
      );
    });
  });
}
