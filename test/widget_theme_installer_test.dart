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
      _writeWidgetThemeHostFiles(appRoot, 'lib/ui/alt');
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
              themeConverterDartPath: 'registry/manifests/theme_converter.dart',
              enabled: true,
            ),
            'alt': RegistryConfigEntry(
              registryMode: 'local',
              registryPath: 'unused',
              installPath: 'lib/ui/alt',
              sharedPath: 'lib/ui/alt/shared',
              themeConverterDartPath: 'registry/manifests/theme_converter.dart',
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

    test('apply and reset are namespace aware', () async {
      final payloadFile = File(p.join(appRoot.path, 'button_theme.json'))
        ..writeAsStringSync(
          jsonEncode({'targetThemeType': 'PrimaryButtonTheme'}),
        );

      final shadcnInstaller = Installer(
        registry: registry,
        targetDir: appRoot.path,
        logger: CliLogger(),
        registryNamespace: 'shadcn',
        registryBaseUrlOverride: tempRoot.path,
        themeConverterDartPathOverride:
            'registry/manifests/theme_converter.dart',
      );
      final altInstaller = Installer(
        registry: registry,
        targetDir: appRoot.path,
        logger: CliLogger(),
        registryNamespace: 'alt',
        registryBaseUrlOverride: tempRoot.path,
        themeConverterDartPathOverride:
            'registry/manifests/theme_converter.dart',
      );

      await shadcnInstaller.applyWidgetThemeFromFile(
          'button', payloadFile.path);

      final shadcnHost = File(
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
      final altHost = File(
        p.join(
          appRoot.path,
          'lib',
          'ui',
          'alt',
          'components',
          'button',
          'button_theme_host.dart',
        ),
      );

      expect(
        shadcnHost.readAsStringSync(),
        contains("const buttonThemeTarget = 'PrimaryButtonTheme';"),
      );
      expect(
        altHost.readAsStringSync(),
        contains("const buttonThemeTarget = '__BUTTON_THEME_TARGET__';"),
      );

      await altInstaller.applyWidgetThemeFromFile('button', payloadFile.path);
      expect(
        altHost.readAsStringSync(),
        contains("const buttonThemeTarget = 'PrimaryButtonTheme';"),
      );

      await altInstaller.resetWidgetTheme('button');
      expect(
        altHost.readAsStringSync(),
        contains("const buttonThemeTarget = '__BUTTON_THEME_TARGET__';"),
      );
      expect(
        shadcnHost.readAsStringSync(),
        contains("const buttonThemeTarget = 'PrimaryButtonTheme';"),
      );
    });

    test('apply from URL stores payload locally before invoking converter',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      server.listen((request) async {
        request.response.write(
          jsonEncode({'targetThemeType': 'PrimaryButtonTheme'}),
        );
        await request.response.close();
      });

      final installer = Installer(
        registry: registry,
        targetDir: appRoot.path,
        logger: CliLogger(),
        registryNamespace: 'shadcn',
        registryBaseUrlOverride: tempRoot.path,
        themeConverterDartPathOverride:
            'registry/manifests/theme_converter.dart',
      );

      await installer.applyWidgetThemeFromUrl(
        'button',
        'http://${server.address.host}:${server.port}/button-theme.json',
      );

      final shadcnHost = File(
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
      expect(
        shadcnHost.readAsStringSync(),
        contains("const buttonThemeSource = 'cache';"),
      );
      expect(
        File(
          p.join(
            appRoot.path,
            '.shadcn',
            'cache',
            'widget_themes',
            'shadcn',
            'button',
            'button-theme.json',
          ),
        ).existsSync(),
        isTrue,
      );
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

  final themeConverter = File(
    p.join(registryRoot.path, 'manifests', 'theme_converter.dart'),
  )..createSync(recursive: true);
  themeConverter.writeAsStringSync(r'''
import 'dart:convert';
import 'dart:io';

String joinPath(String left, String right) {
  if (left.isEmpty) {
    return right;
  }
  if (left.endsWith('/') || left.endsWith('\\')) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
}

Future<void> main(List<String> args) async {
  final request = jsonDecode(await File(args.first).readAsString())
      as Map<String, dynamic>;
  if (request['scope'] != 'widget') {
    stdout.write(jsonEncode({
      'scope': request['scope'],
      'installPlan': {'operations': []}
    }));
    return;
  }

  final context = request['context'] as Map<String, dynamic>? ?? const {};
  final installPath = context['installPath']?.toString() ?? '';
  final namespace = request['namespace']?.toString() ?? '';
  final componentId = request['componentId']?.toString() ?? '';
  final hostPath = joinPath(
    joinPath(joinPath(installPath, 'components'), componentId),
    'button_theme_host.dart',
  );
  final generatedPath = joinPath(
    joinPath(joinPath(installPath, 'components'), componentId),
    'generated_${namespace}_theme.dart',
  );

  if (request['action'] == 'reset') {
    stdout.write(jsonEncode({
      'scope': 'widget',
      'resolvedNamespace': namespace,
      'resolvedComponent': componentId,
      'installPlan': {
        'operations': [
          {
            'type': 'write_file',
            'path': hostPath,
            'content': "const buttonThemeTarget = '__BUTTON_THEME_TARGET__';\nconst buttonThemeSource = '__BUTTON_THEME_SOURCE__';\n",
          },
          {
            'type': 'delete_file',
            'path': generatedPath,
          }
        ]
      }
    }));
    return;
  }

  final payloadFile = request['payloadFile']?.toString() ?? '';
  final payload =
      jsonDecode(await File(payloadFile).readAsString()) as Map<String, dynamic>;
  final selectedTarget = payload['targetThemeType']?.toString() ?? 'global';
  stdout.write(jsonEncode({
    'scope': 'widget',
    'resolvedNamespace': namespace,
    'resolvedComponent': componentId,
    'resolvedTargetThemeType': selectedTarget,
    'installPlan': {
      'operations': [
        {
          'type': 'patch_file',
          'path': hostPath,
          'find': '__BUTTON_THEME_TARGET__',
          'replace': selectedTarget,
        },
        {
          'type': 'patch_file',
          'path': hostPath,
          'find': '__BUTTON_THEME_SOURCE__',
          'replace': 'cache',
        },
        {
          'type': 'write_file',
          'path': generatedPath,
          'content': "const activeButtonTheme = '${selectedTarget}';\n",
        }
      ]
    }
  }));
}
''');
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
