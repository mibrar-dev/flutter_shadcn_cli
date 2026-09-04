import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_shadcn_cli/src/application/services/command_health/audit_command.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/installer.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/dry_run_command.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('production QA regressions', () {
    late Directory tempRoot;
    late Directory registryRoot;
    late Directory appRoot;
    late String cliEntrypoint;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('production_qa_');
      registryRoot = Directory(p.join(tempRoot.path, 'registry'))
        ..createSync(recursive: true);
      appRoot = Directory(p.join(tempRoot.path, 'app'))..createSync();
      await _writePubspec(appRoot);
      await ShadcnConfig.save(
        appRoot.path,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
        ),
      );
      cliEntrypoint = await _cliEntrypoint();
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('dry-run --all includes only registry components', () async {
      _writeRegistry(
        registryRoot,
        components: [
          _component('button'),
        ],
      );
      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(tempRoot.path),
        skipIntegrity: true,
      );
      final installer = Installer(
        registry: registry,
        targetDir: appRoot.path,
        logger: CliLogger(useColor: false),
      );
      final args = buildCliParser()
          .parse(normalizeCliArgs(['dry-run', '--all', '--json']));

      final code = await runDryRunCommand(
        dryRunCommand: args.command!,
        installer: installer,
      );

      expect(code, ExitCodes.success);
    });

    test('doctor validates v1 manifests schema when root schema is absent',
        () async {
      _writeRegistry(
        registryRoot,
        components: [
          _component('button'),
        ],
        schemaUnderManifests: true,
      );
      File(
        p.join(
          appRoot.path,
          'lib',
          'ui',
          'shadcn',
          'shared',
          'theme',
          'color_scheme.dart',
        ),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync('class ColorScheme {}');

      final result = await Process.run(
        'dart',
        [
          cliEntrypoint,
          '--advanced',
          '--registry-path',
          registryRoot.path,
          '--skip-integrity',
          'doctor',
          '--json',
        ],
        workingDirectory: appRoot.path,
      );

      expect(result.exitCode, ExitCodes.success);
    });

    test('audit ignores optional preview files excluded by project config',
        () async {
      _writeRegistry(
        registryRoot,
        components: [
          _component(
            'button',
            files: [
              _file('registry/components/button/button.dart',
                  '{installPath}/components/button/button.dart'),
              _file('registry/components/button/_button_preview_state.dart',
                  '{installPath}/components/button/_button_preview_state.dart'),
            ],
          ),
        ],
      );
      File(
        p.join(
          appRoot.path,
          '.shadcn',
          'components',
          'button.json',
        ),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'id': 'button'}));
      File(
        p.join(
          appRoot.path,
          'lib',
          'ui',
          'shadcn',
          'components',
          'button',
          'button.dart',
        ),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync('class Button {}');
      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(tempRoot.path),
        skipIntegrity: true,
      );

      final code = await runAuditCommand(
        registry: registry,
        targetDir: appRoot.path,
        config: const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includePreview: false,
        ),
        jsonOutput: false,
        logger: CliLogger(useColor: false),
      );

      expect(code, ExitCodes.success);
    });

    test('explicit missing registry path after command is rejected locally',
        () async {
      final result = await Process.run(
        'dart',
        [
          cliEntrypoint,
          '--advanced',
          'list',
          '--registry-path',
          p.join(tempRoot.path, 'missing_registry'),
        ],
        workingDirectory: appRoot.path,
      );

      expect(result.exitCode, ExitCodes.registryNotFound);
      expect(result.stdout.toString(), isNot(contains('baseUrl')));
      expect(result.stderr.toString(), contains('Local registry not found'));
    });

    test('init installs shared app and localization modules by default',
        () async {
      _writeRegistry(
        registryRoot,
        shared: [
          _shared('theme'),
          _shared('app_theme'),
          _shared('util'),
          _shared('color_extensions'),
          _shared('form_control'),
          _shared('form_value_supplier'),
          _shared('localizations'),
          _shared('localizations_extensions'),
        ],
        components: [
          _component('button'),
        ],
      );
      final registry = await Registry.load(
        registryRoot: RegistryLocation.local(registryRoot.path),
        sourceRoot: RegistryLocation.local(tempRoot.path),
        skipIntegrity: true,
      );
      final installer = Installer(
        registry: registry,
        targetDir: appRoot.path,
        logger: CliLogger(useColor: false),
      );

      await installer.init(skipPrompts: true);

      expect(
        File(p.join(appRoot.path, 'lib', 'ui', 'shadcn', 'shared', 'app_theme',
                'app_theme.dart'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(appRoot.path, 'lib', 'ui', 'shadcn', 'shared',
                'localizations', 'localizations.dart'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(appRoot.path, 'lib', 'ui', 'shadcn', 'shared',
                'localizations_extensions', 'localizations_extensions.dart'))
            .existsSync(),
        isTrue,
      );
    });
  });
}

Future<String> _cliEntrypoint() async {
  final configUri = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_shadcn_cli/src/config.dart'),
  );
  if (configUri == null || !configUri.isScheme('file')) {
    throw StateError('Could not resolve flutter_shadcn_cli package root');
  }

  final libDir = p.dirname(p.dirname(p.fromUri(configUri)));
  return p.join(p.dirname(libDir), 'bin', 'shadcn.dart');
}

Future<void> _writePubspec(Directory root) {
  return File(p.join(root.path, 'pubspec.yaml')).writeAsString(
    [
      'name: production_qa_test',
      'environment:',
      '  sdk: ^3.3.0',
      'dependencies:',
      '  flutter:',
      '    sdk: flutter',
    ].join('\n'),
  );
}

void _writeRegistry(
  Directory root, {
  required List<Map<String, Object?>> components,
  List<Map<String, Object?>> shared = const [],
  bool schemaUnderManifests = false,
}) {
  for (final item in shared) {
    final id = item['id'] as String;
    File(p.join(root.path, 'shared', id, '$id.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('class ${_pascal(id)}Shared {}');
  }

  File(p.join(root.path, 'components.json')).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      r'$schema': './components.schema.json',
      'schemaVersion': 1,
      'name': 'production_qa_registry',
      'defaults': {
        'installPath': 'lib/ui/shadcn',
        'sharedPath': 'lib/ui/shadcn/shared',
      },
      'shared': shared,
      'components': components,
    }),
  );
  final schemaPath = schemaUnderManifests
      ? p.join(root.path, 'manifests', 'components.schema.json')
      : p.join(root.path, 'components.schema.json');
  File(schemaPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode({
        r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        'type': 'object',
        'required': ['schemaVersion', 'name', 'defaults', 'components'],
        'properties': {
          'schemaVersion': {'type': 'integer'},
          'name': {'type': 'string'},
          'defaults': {'type': 'object'},
          'shared': {'type': 'array'},
          'components': {'type': 'array'},
        },
      }),
    );
}

Map<String, Object?> _shared(String id) {
  return {
    'id': id,
    'files': [
      _file('registry/shared/$id/$id.dart', '{sharedPath}/$id/$id.dart'),
    ],
  };
}

String _pascal(String value) {
  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join();
}

Map<String, Object?> _component(
  String id, {
  List<Map<String, String>>? files,
}) {
  return {
    'id': id,
    'name': id,
    'files': files ??
        [
          _file(
            'registry/components/$id/$id.dart',
            '{installPath}/components/$id/$id.dart',
          ),
        ],
    'shared': const [],
    'dependsOn': const [],
    'pubspec': {'dependencies': const {}},
    'assets': const [],
    'postInstall': const [],
  };
}

Map<String, String> _file(String source, String destination) {
  return {
    'source': source,
    'destination': destination,
  };
}
