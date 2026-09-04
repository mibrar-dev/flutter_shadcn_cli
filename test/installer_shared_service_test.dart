import 'dart:async';
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

    test(
      'resolves sibling Dart imports without dot prefixes as relative imports',
      () async {
        _writeSource(
          registryDir,
          'registry/shared/primitives/clickable.dart',
          "import 'focus_outline.dart';\nclass Clickable {}\n",
        );
        _writeSource(
          registryDir,
          'registry/shared/primitives/focus_outline.dart',
          'class FocusOutline {}\n',
        );
        final service = InstallerSharedService(
          registry: _registry(
            registryDir,
            shared: [
              _shared(
                'clickable',
                source: 'registry/shared/primitives/clickable.dart',
              ),
              _shared(
                'focus_outline',
                source: 'registry/shared/primitives/focus_outline.dart',
              ),
            ],
          ),
          logger: CliLogger(),
        );

        final closure = await service.resolveSharedDependencyClosure({
          'clickable',
        });

        expect(closure, {'clickable', 'focus_outline'});
      },
    );

    test(
      'ignores imports between files owned by the same shared item',
      () async {
        _writeSource(
          registryDir,
          'registry/shared/clickable/clickable.dart',
          "import '_impl/clickable_state.dart';\nclass Clickable {}\n",
        );
        _writeSource(
          registryDir,
          'registry/shared/clickable/_impl/clickable_state.dart',
          'class ClickableState {}\n',
        );
        final service = InstallerSharedService(
          registry: _registry(
            registryDir,
            shared: [
              _sharedFiles('clickable', [
                'registry/shared/clickable/clickable.dart',
                'registry/shared/clickable/_impl/clickable_state.dart',
              ]),
            ],
          ),
          logger: CliLogger(),
        );

        final dependencies = await service.loadSharedDependencies('clickable');

        expect(dependencies, isEmpty);
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

    test('starts shared item file installs concurrently', () async {
      final service = InstallerSharedService(
        registry: _registry(
          registryDir,
          shared: [
            _sharedFiles('theme', [
              'registry/shared/theme/a.txt',
              'registry/shared/theme/b.txt',
            ]),
          ],
        ),
        logger: CliLogger(),
      );
      final release = Completer<void>();
      var active = 0;
      var maxActive = 0;
      var started = 0;

      await service.installShared(
        'theme',
        ensureConfigLoaded: () async {},
        installComponent: (_) async {
          fail('component fallback should not be used for existing shared ids');
        },
        installFileWithDependencies: (file, availableFiles, {sharedId}) async {
          active++;
          started++;
          if (active > maxActive) {
            maxActive = active;
          }
          if (started == 2 && !release.isCompleted) {
            release.complete();
          }
          await release.future;
          active--;
        },
      ).timeout(const Duration(milliseconds: 250));

      expect(maxActive, greaterThan(1));
    });

    test('installs mutually importing shared items without recursion failure',
        () async {
      _writeSource(
        registryDir,
        'registry/shared/theme/theme.dart',
        "import '../color_scheme/color_scheme.dart';\nclass ThemeTokens {}\n",
      );
      _writeSource(
        registryDir,
        'registry/shared/color_scheme/color_scheme.dart',
        "import '../theme/theme.dart';\nclass ColorSchemeTokens {}\n",
      );
      final service = InstallerSharedService(
        registry: _registry(
          registryDir,
          shared: [
            _shared('theme', source: 'registry/shared/theme/theme.dart'),
            _shared(
              'color_scheme',
              source: 'registry/shared/color_scheme/color_scheme.dart',
            ),
          ],
        ),
        logger: CliLogger(),
      );
      final installed = <String>[];

      await service.installShared(
        'theme',
        ensureConfigLoaded: () async {},
        installComponent: (_) async {
          fail('component fallback should not be used for existing shared ids');
        },
        installFileWithDependencies: (file, availableFiles, {sharedId}) async {
          installed.add('$sharedId:${file.source}');
        },
      );

      expect(installed, [
        'color_scheme:registry/shared/color_scheme/color_scheme.dart',
        'theme:registry/shared/theme/theme.dart',
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

Map<String, dynamic> _sharedFiles(String id, List<String> sources) {
  return {
    'id': id,
    'files': [
      for (final source in sources)
        {'source': source, 'destination': '{sharedPath}/$id.dart'},
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
