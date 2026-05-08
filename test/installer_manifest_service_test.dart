import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer_manifest_service.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('InstallerManifestService', () {
    late Directory projectDir;
    late Registry registry;
    late InstallerManifestService service;

    setUp(() {
      projectDir = Directory.systemTemp.createTempSync(
        'installer_manifest_service_',
      );
      registry = Registry(
        {
          'components': [
            _componentJson('button', version: '1.0.0'),
          ],
        },
        RegistryLocation.local(projectDir.path),
        RegistryLocation.local(projectDir.path),
      );
      service = InstallerManifestService(
        targetDir: projectDir.path,
        registry: registry,
        registryNamespace: 'shadcn',
        registryBaseUrlOverride: '/registry',
      );
    });

    tearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    test('writes aggregate and per-component manifests', () async {
      final button = registry.getComponent('button')!;

      await service.updateAggregateManifest(
        installPath: 'lib/ui/shadcn',
        sharedPath: 'lib/ui/shadcn/shared',
        installedComponentIds: {'button'},
        managedDependencies: {'gap': '^3.0.1'},
      );
      await service.writeComponentManifest(
        button,
        localeResourcesInstalled: [
          {
            'locale': 'en',
            'format': 'json',
            'destination': 'lib/l10n/app_en.arb',
            'required': true,
            'addedKeys': ['shadcn.button.label'],
          },
        ],
      );

      final aggregate = _readJson(
        p.join(projectDir.path, 'lib/ui/shadcn/components.json'),
      );
      expect(aggregate['installed'], ['button']);
      expect(aggregate['managedDependencies'], ['gap']);
      expect(aggregate['sharedPath'], 'lib/ui/shadcn/shared');

      final manifest = _readJson(
        p.join(projectDir.path, '.shadcn/components/button.json'),
      );
      expect(manifest['registryNamespace'], 'shadcn');
      expect(manifest['registrySource'], '/registry');
      expect(manifest['locale'], isA<Map<String, dynamic>>());
    });

    test('preserves installedAt when rewriting component manifest', () async {
      final button = registry.getComponent('button')!;
      await service.writeComponentManifest(button);
      final first = _readJson(
        p.join(projectDir.path, '.shadcn/components/button.json'),
      )['installedAt'];

      await service.writeComponentManifest(button);
      final second = _readJson(
        p.join(projectDir.path, '.shadcn/components/button.json'),
      )['installedAt'];

      expect(second, first);
    });

    test('clears per-component manifests when aggregate install set is empty',
        () async {
      final button = registry.getComponent('button')!;
      await service.writeComponentManifest(button);

      await service.updateAggregateManifest(
        installPath: 'lib/ui/shadcn',
        sharedPath: 'lib/ui/shadcn/shared',
        installedComponentIds: const {},
        managedDependencies: const {},
      );

      expect(
        File(p.join(projectDir.path, 'lib/ui/shadcn/components.json'))
            .existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(projectDir.path, '.shadcn/components')).existsSync(),
        isFalse,
      );
    });
  });
}

Map<String, dynamic> _componentJson(String id, {String? version}) {
  return {
    'id': id,
    'name': id[0].toUpperCase() + id.substring(1),
    'version': version,
    'tags': ['core'],
    'files': const [],
    'shared': const [],
    'dependsOn': const [],
  };
}

Map<String, dynamic> _readJson(String path) {
  return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
}
