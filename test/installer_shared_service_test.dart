import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer_shared_service.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('InstallerSharedService', () {
    late Directory tempDir;
    late Directory registryDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('installer_shared_');
      registryDir = Directory(p.join(tempDir.path, 'registry'))
        ..createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('normalizes legacy utils id to util', () {
      final service = InstallerSharedService(
        registry: _registry(registryDir),
        logger: CliLogger(),
      );

      expect(service.normalizeSharedId('utils'), 'util');
      expect(service.normalizeSharedId('theme'), 'theme');
    });

    test('includes optional color_scheme in core init ids when present', () {
      final service = InstallerSharedService(
        registry: _registry(registryDir, shared: [_shared('color_scheme')]),
        logger: CliLogger(),
      );

      expect(service.coreSharedIdsForInit(), contains('color_scheme'));
    });

    test(
      'resolves shared dependency closure from relative Dart imports',
      () async {
        _writeSource(
          registryDir,
          'registry/shared/util/util.dart',
          "export '../theme/theme.dart';\nclass Util {}\n",
        );
        _writeSource(
          registryDir,
          'registry/shared/theme/theme.dart',
          'class ThemeTokens {}\n',
        );
        final service = InstallerSharedService(
          registry: _registry(
            registryDir,
            shared: [
              _shared('util', source: 'registry/shared/util/util.dart'),
              _shared('theme', source: 'registry/shared/theme/theme.dart'),
            ],
          ),
          logger: CliLogger(),
        );

        final closure = await service.resolveSharedDependencyClosure({'utils'});

        expect(closure, {'util', 'theme'});
      },
    );

    test('installs shared dependencies before owning shared item', () async {
      _writeSource(
        registryDir,
        'registry/shared/util/util.dart',
        "import '../theme/theme.dart';\nclass Util {}\n",
      );
      _writeSource(
        registryDir,
        'registry/shared/theme/theme.dart',
        'class ThemeTokens {}\n',
      );
      final service = InstallerSharedService(
        registry: _registry(
          registryDir,
          shared: [
            _shared('util', source: 'registry/shared/util/util.dart'),
            _shared('theme', source: 'registry/shared/theme/theme.dart'),
          ],
        ),
        logger: CliLogger(),
      );
      final installed = <String>[];

      await service.installShared(
        'util',
        ensureConfigLoaded: () async {},
        installComponent: (_) async {
          fail('component fallback should not be used for existing shared ids');
        },
        installFileWithDependencies: (file, availableFiles, {sharedId}) async {
          installed.add('$sharedId:${file.source}');
        },
      );

      expect(installed, [
        'theme:registry/shared/theme/theme.dart',
        'util:registry/shared/util/util.dart',
      ]);
    });

    test(
      'falls back to component install when shared id is a component',
      () async {
        final service = InstallerSharedService(
          registry: _registry(registryDir, components: [_component('button')]),
          logger: CliLogger(),
        );
        final installedComponents = <String>[];

        await service.installShared(
          'button',
          ensureConfigLoaded: () async {},
          installComponent: (id) async {
            installedComponents.add(id);
          },
          installFileWithDependencies: (_, __, {sharedId}) async {
            fail('shared file install should not run for component fallback');
          },
        );

        expect(installedComponents, ['button']);
      },
    );
  });
}

void _writeSource(Directory registryDir, String relativePath, String content) {
  final file = File(
    p.joinAll([registryDir.path, ...relativePath.split('/')]),
  );
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

Registry _registry(
  Directory registryDir, {
  List<Map<String, dynamic>> shared = const [],
  List<Map<String, dynamic>> components = const [],
}) {
  return Registry(
    {'components': components, 'shared': shared},
    RegistryLocation.local(registryDir.path),
    RegistryLocation.local(registryDir.path),
  );
}

Map<String, dynamic> _shared(String id, {String? source}) {
  final fileSource = source ?? 'registry/shared/$id/$id.dart';
  return {
    'id': id,
    'files': [
      {'source': fileSource, 'destination': '{sharedPath}/$id.dart'},
    ],
  };
}

Map<String, dynamic> _component(String id) {
  return {
    'id': id,
    'name': id,
    'files': [
      {
        'source': 'registry/components/$id/$id.dart',
        'destination': '{installPath}/components/$id/$id.dart',
      },
    ],
    'shared': [],
    'dependsOn': [],
    'pubspec': {'dependencies': <String, dynamic>{}},
  };
}
