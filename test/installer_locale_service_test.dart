import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer_locale_service.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('InstallerLocaleService', () {
    late Directory projectDir;
    late Directory sourceDir;
    late Registry registry;

    setUp(() {
      projectDir = Directory.systemTemp.createTempSync(
        'installer_locale_service_project_',
      );
      sourceDir = Directory.systemTemp.createTempSync(
        'installer_locale_service_source_',
      );
      registry = Registry(
        {
          'components': [
            _componentJson('button'),
          ],
        },
        RegistryLocation.local(sourceDir.path),
        RegistryLocation.local(sourceDir.path),
      );
    });

    tearDown(() {
      for (final dir in [projectDir, sourceDir]) {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      }
    });

    test('merges only missing component locale keys into project ARB',
        () async {
      File(p.join(projectDir.path, 'l10n.yaml')).writeAsStringSync('''
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
''');
      final arbDir = Directory(p.join(projectDir.path, 'lib', 'l10n'))
        ..createSync(recursive: true);
      File(p.join(arbDir.path, 'app_en.arb')).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          '@@locale': 'en',
          'buttonSave': 'Keep existing',
        }),
      );
      final resourceFile = File(
        p.join(
          sourceDir.path,
          'registry',
          'components',
          'control',
          'button',
          'locales',
          'en.json',
        ),
      )..createSync(recursive: true);
      resourceFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'buttonSave': 'Save',
          'buttonCancel': 'Cancel',
          '@buttonCancel': {'description': 'Cancel action label'},
        }),
      );

      final service = InstallerLocaleService(
        registry: registry,
        targetDir: projectDir.path,
        logger: CliLogger(),
      );

      final installed = await service.installLocaleResources(
        registry.getComponent('button')!,
      );

      final appArb = jsonDecode(
        File(p.join(arbDir.path, 'app_en.arb')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(appArb['buttonSave'], 'Keep existing');
      expect(appArb['buttonCancel'], 'Cancel');
      expect(appArb['@buttonCancel'], {'description': 'Cancel action label'});
      expect(installed.single['destination'], 'lib/l10n/app_en.arb');
      expect(installed.single['addedKeys'], [
        '@buttonCancel',
        'buttonCancel',
      ]);
    });
  });
}

Map<String, dynamic> _componentJson(String id) {
  return {
    'id': id,
    'name': id,
    'category': 'control',
    'tags': const [],
    'files': const [],
    'shared': const [],
    'dependsOn': const [],
    'locale': {
      'defaultLocale': 'en',
      'required': ['en'],
      'resources': [
        {
          'locale': 'en',
          'format': 'json',
          'source': 'registry/components/control/button/locales/en.json',
          'required': true,
        },
      ],
    },
  };
}
