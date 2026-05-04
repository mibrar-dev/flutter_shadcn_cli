import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/installer.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Widget theme installer', () {
    late Directory tempRoot;
    late Directory registryRoot;
    late Directory appRoot;
    late Registry registry;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('widget_theme_installer_');
      registryRoot = Directory(p.join(tempRoot.path, 'registry'))..createSync();
      appRoot = Directory(p.join(tempRoot.path, 'app'))..createSync();
      _writeRegistryFixtures(registryRoot);
      _writePubspec(appRoot);
      _writeWidgetThemeHostFiles(appRoot, 'lib/ui/shadcn');
      await ShadcnConfig.save(
        appRoot.path,
        const ShadcnConfig(
          defaultNamespace: 'shadcn',
          registries: {
            'shadcn': RegistryConfigEntry(
              registryMode: 'local',
              registryPath: 'unused',
              installPath: 'lib/ui/shadcn',
              sharedPath: 'lib/ui/shadcn/shared',
              enabled: true,
            ),
          },
        ),
      );
      registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(tempRoot.path),
      );
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('apply from file fails explicitly without modifying widget files',
        () async {
      final payloadFile = File(p.join(appRoot.path, 'button_theme.json'))
        ..writeAsStringSync(
          jsonEncode({
            'name': 'button-theme',
            'label': 'Button Theme',
            'files': [
              {
                'source': 'https://example.com/button_theme.dart',
                'target':
                    'lib/ui/shadcn/components/button/generated_button_theme.dart',
                'sha256': '0' * 64,
              }
            ],
          }),
        );
      final installer = Installer(
        registry: registry,
        targetDir: appRoot.path,
        logger: CliLogger(),
        registryNamespace: 'shadcn',
        registryBaseUrlOverride: tempRoot.path,
      );

      final hostFile = File(
        p.join(
          appRoot.path,
          'lib',
          'ui',
          'shadcn',
          'components',
          'button',
          'button_theme_host.dart',
        ),
      );
      final before = hostFile.readAsStringSync();

      await expectLater(
        installer.applyWidgetThemeFromFile('button', payloadFile.path),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('experimental'),
          ),
        ),
      );
      expect(hostFile.readAsStringSync(), before);
    });

    test('reset fails explicitly without modifying widget files', () async {
      final installer = Installer(
        registry: registry,
        targetDir: appRoot.path,
        logger: CliLogger(),
        registryNamespace: 'shadcn',
        registryBaseUrlOverride: tempRoot.path,
      );

      final hostFile = File(
        p.join(
          appRoot.path,
          'lib',
          'ui',
          'shadcn',
          'components',
          'button',
          'button_theme_host.dart',
        ),
      );
      final before = hostFile.readAsStringSync();

      await expectLater(
        installer.resetWidgetTheme('button'),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('experimental'),
          ),
        ),
      );
      expect(hostFile.readAsStringSync(), before);
    });
  });
}

void _writeRegistryFixtures(Directory registryRoot) {
  final sharedThemeDir = Directory(p.join(registryRoot.path, 'shared', 'theme'))
    ..createSync(recursive: true);
  File(p.join(sharedThemeDir.path, 'theme.dart'))
      .writeAsStringSync('class ThemeHelper {}');

  final registryJson = {
    'schemaVersion': 1,
    'name': 'test_registry',
    'defaults': {
      'installPath': 'lib/ui/shadcn',
      'sharedPath': 'lib/ui/shadcn/shared',
    },
    'shared': [
      {
        'id': 'theme',
        'files': [
          {
            'source': 'registry/shared/theme/theme.dart',
            'destination': '{sharedPath}/theme/theme.dart'
          }
        ]
      }
    ],
    'components': [
      {
        'id': 'button',
        'name': 'Button',
        'description': 'Button component',
        'category': 'control',
        'version': '1.0.0',
        'tags': ['core'],
        'files': const [],
        'shared': ['theme'],
        'dependsOn': const [],
        'pubspec': {'dependencies': {}},
        'assets': const [],
        'postInstall': const [],
      }
    ]
  };

  File(p.join(registryRoot.path, 'components.json')).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(registryJson),
  );
  File(p.join(registryRoot.path, 'components.schema.json'))
      .writeAsStringSync(jsonEncode({}));
}

void _writePubspec(Directory targetRoot) {
  final buffer = StringBuffer()
    ..writeln('name: test_app')
    ..writeln('environment:')
    ..writeln('  sdk: ">=3.3.0 <4.0.0"')
    ..writeln('dependencies:')
    ..writeln('  flutter:')
    ..writeln('    sdk: flutter');
  File(p.join(targetRoot.path, 'pubspec.yaml'))
      .writeAsStringSync(buffer.toString());
}

void _writeWidgetThemeHostFiles(Directory targetRoot, String installPath) {
  final hostFile = File(
    p.join(
      targetRoot.path,
      installPath,
      'components',
      'button',
      'button_theme_host.dart',
    ),
  )..createSync(recursive: true);
  hostFile.writeAsStringSync(
    "const buttonThemeTarget = '__BUTTON_THEME_TARGET__';\n"
    "const buttonThemeSource = '__BUTTON_THEME_SOURCE__';\n",
  );
}
