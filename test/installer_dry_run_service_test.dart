import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer_config_resolver.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_dry_run_service.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('InstallerDryRunService', () {
    late Directory tempDir;
    late Directory registryRoot;
    late Directory targetRoot;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dry_run_service_test_');
      registryRoot = Directory(p.join(tempDir.path, 'registry'))..createSync();
      targetRoot = Directory(p.join(tempDir.path, 'app'))..createSync();
      _writeRegistry(registryRoot);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('builds dependency-aware plan with configured destinations', () async {
      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(tempDir.path),
      );
      final service = InstallerDryRunService(
        registry: registry,
        targetDir: targetRoot.path,
        config: const ShadcnConfig(
          installPath: 'lib/custom/ui',
          sharedPath: 'lib/custom/ui/shared',
        ),
        configResolver: InstallerConfigResolver(registry: registry),
        logger: CliLogger(),
      );

      final plan = await service.buildPlan(['dialog']);

      expect(plan.requested, ['dialog']);
      expect(plan.missing, isEmpty);
      expect(plan.components.map((component) => component.id), [
        'button',
        'dialog',
      ]);
      expect(plan.dependencyGraph['dialog'], ['button']);
      expect(plan.pubspecDependencies, {'gap': '^3.0.1'});
      expect(plan.shared, ['util']);
      expect(plan.componentFiles['button'], [
        {
          'source': 'registry/components/button/button.dart',
          'destination': p.join(
            targetRoot.path,
            'lib/custom/ui/components/button/button.dart',
          ),
        }
      ]);
    });
  });
}

void _writeRegistry(Directory registryRoot) {
  final sourceRoot = p.dirname(registryRoot.path);
  Directory(p.join(sourceRoot, 'registry', 'components', 'button'))
      .createSync(recursive: true);
  Directory(p.join(sourceRoot, 'registry', 'components', 'dialog'))
      .createSync(recursive: true);
  File(p.join(registryRoot.path, 'components.json')).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'defaults': {
        'installPath': 'lib/ui/shadcn',
        'sharedPath': 'lib/ui/shadcn/shared',
      },
      'shared': [
        {
          'id': 'util',
          'files': [
            {
              'source': 'registry/shared/util.dart',
              'destination': '{sharedPath}/util.dart',
            }
          ],
        }
      ],
      'components': [
        {
          'id': 'button',
          'name': 'Button',
          'files': [
            {
              'source': 'registry/components/button/button.dart',
              'destination': '{installPath}/components/button/button.dart',
            }
          ],
          'shared': ['utils'],
          'dependsOn': [],
          'pubspec': {
            'dependencies': {'gap': '^3.0.1'},
          },
        },
        {
          'id': 'dialog',
          'name': 'Dialog',
          'files': [
            {
              'source': 'registry/components/dialog/dialog.dart',
              'destination': '{installPath}/components/dialog/dialog.dart',
            }
          ],
          'shared': [],
          'dependsOn': ['button'],
          'pubspec': {'dependencies': {}},
        },
      ],
    }),
  );
  File(p.join(registryRoot.path, 'components.schema.json'))
      .writeAsStringSync(jsonEncode({}));
}
