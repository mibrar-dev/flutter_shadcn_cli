import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/shadcn.dart' as cli;
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';

late final String _cliEntrypoint;

void main() {
  _cliEntrypoint = p.join(Directory.current.path, 'bin', 'shadcn.dart');

  group('CLI integration', () {
    late Directory tempRoot;
    late Directory registryRoot;
    late Directory appRoot;
    late Directory originalCwd;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('shadcn_cli_it_');
      registryRoot = Directory(p.join(tempRoot.path, 'registry'))..createSync();
      appRoot = Directory(p.join(tempRoot.path, 'app'))..createSync();
      _writeRegistryFixtures(registryRoot);
      _writePubspec(appRoot);
      await ShadcnConfig.save(
        appRoot.path,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
          includeMeta: true,
          classPrefix: 'App',
        ),
      );
      originalCwd = Directory.current;
      Directory.current = appRoot;
    });

    tearDown(() {
      exitCode = 0;
      Directory.current = originalCwd;
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('add installs component and writes manifests', () async {
      await cli.main([
        '--advanced',
        '--offline',
        'add',
        'button',
        '--registry-path',
        registryRoot.path,
      ]);

      final installDir = p.join(
        appRoot.path,
        'lib',
        'ui',
        'shadcn',
        'components',
        'button',
      );
      expect(File(p.join(installDir, 'button.dart')).existsSync(), isTrue);
      expect(File(p.join(installDir, 'meta.json')).existsSync(), isTrue);
      expect(File(p.join(installDir, 'README.md')).existsSync(), isFalse);
      expect(File(p.join(installDir, 'preview.dart')).existsSync(), isFalse);
      expect(
        File(p.join(installDir, 'preview_state.dart')).existsSync(),
        isFalse,
      );
      expect(
        File(
          p.join(
            appRoot.path,
            'lib',
            'ui',
            'shadcn',
            'shared',
            'theme',
            'theme.dart',
          ),
        ).existsSync(),
        isTrue,
      );

      final manifestFile = File(
        p.join(appRoot.path, '.shadcn', 'components', 'button.json'),
      );
      expect(manifestFile.existsSync(), isTrue);
      final manifestData =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      expect(manifestData['id'], 'button');
      expect(manifestData['version'], '1.0.0');
      expect(manifestData['tags'], contains('core'));

      final installManifest = File(
        p.join(appRoot.path, 'lib', 'ui', 'shadcn', 'components.json'),
      );
      expect(installManifest.existsSync(), isTrue);
      final installData = jsonDecode(installManifest.readAsStringSync())
          as Map<String, dynamic>;
      final meta = installData['componentMeta'] as Map<String, dynamic>;
      final buttonMeta = meta['button'] as Map<String, dynamic>;
      expect(buttonMeta['version'], '1.0.0');
      expect(buttonMeta['tags'], contains('core'));

      final aliasFile = File(
        p.join(appRoot.path, 'lib', 'ui', 'shadcn', 'app_components.dart'),
      );
      expect(aliasFile.existsSync(), isTrue);
      final aliasContents = aliasFile.readAsStringSync();
      expect(aliasContents,
          contains("export 'package:flutter/material.dart' hide"));
      expect(aliasContents, contains('    Button;'));
      expect(
          aliasContents, contains("export 'components/button/button.dart';"));
      expect(aliasContents, contains('typedef AppButton = Button;'));
    });

    test('doctor runs without crashing', () async {
      await cli.main([
        '--advanced',
        'doctor',
        '--registry-path',
        registryRoot.path,
      ]);
    });

    test('init rejects multiple positional namespace tokens', () async {
      final result = await _runCli(
        cwd: appRoot.path,
        args: [
          'init',
          '--yes',
          'button',
          'dialog',
        ],
      );

      expect(result.exitCode, ExitCodes.usage);
      expect(result.stderr, contains('Usage: flutter_shadcn init'));
    });

    test('init --install-fonts is rejected by parser', () async {
      final result = await _runCli(
        cwd: appRoot.path,
        args: [
          'init',
          '--yes',
          '--install-fonts',
        ],
      );

      expect(result.exitCode, ExitCodes.usage);
      expect(result.stdout, contains('install-fonts'));
    });

    test('docs command requires advanced mode', () async {
      final result = await _runCli(
        cwd: appRoot.path,
        args: ['docs', '--generate'],
      );

      expect(result.exitCode, ExitCodes.usage);
      expect(result.stderr, contains('requires --advanced'));
    });

    test('advanced flag works after command', () async {
      final result = await _runCli(
        cwd: appRoot.path,
        args: ['docs', '--advanced', '--help'],
      );

      expect(result.exitCode, ExitCodes.success);
    });

    test('json flag works in any position for json-enabled commands', () async {
      final listResult = await _runCli(
        cwd: appRoot.path,
        args: [
          '--advanced',
          '--offline',
          '--json',
          'list',
          '--registry-path',
          registryRoot.path,
        ],
      );

      expect(listResult.exitCode, ExitCodes.success);
      expect(jsonDecode(listResult.stdout), isA<Map<String, dynamic>>());

      final registriesResult = await _runCli(
        cwd: appRoot.path,
        args: [
          '--advanced',
          '--offline',
          'registries',
          '--json',
        ],
      );

      expect(registriesResult.exitCode, ExitCodes.success);
      expect(jsonDecode(registriesResult.stdout), isA<Map<String, dynamic>>());
    });

    test(
        'list uses registries directory manifest paths without persisted config',
        () async {
      final manifestRegistry =
          Directory(p.join(tempRoot.path, 'manifest_registry', 'registry'))
            ..createSync(recursive: true);
      File(p.join(manifestRegistry.path, 'manifests', 'index.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'components': [
              {
                'id': 'button',
                'name': 'Button',
                'category': 'control',
                'description': 'Button component',
                'tags': ['core'],
                'install': 'flutter_shadcn add button',
                'import': 'package:app/ui/shadcn/components/button/button.dart',
                'importPath': 'ui/shadcn/components/button/button.dart',
                'api': {},
                'examples': {},
                'dependencies': {},
                'related': [],
              }
            ]
          }),
        );
      File(p.join(manifestRegistry.path, 'manifests', 'components.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(_emptyComponentsJson());

      final registriesFile = _writeRegistriesFile(appRoot, [
        {
          'id': 'official',
          'displayName': 'Official',
          'maintainers': ['team'],
          'repo': 'https://example.com/repo',
          'license': 'MIT',
          'minCliVersion': '0.1.0',
          'baseUrl': 'https://example.com/registry-root/',
          'paths': {
            'componentsJson': 'registry/manifests/components.json',
            'indexJson': 'registry/manifests/index.json',
          },
          'install': {'namespace': 'shadcn', 'root': 'lib/ui/shadcn'},
        }
      ]);

      final result = await _runCli(
        cwd: appRoot.path,
        args: [
          '--advanced',
          '--registries-path',
          registriesFile,
          '--registry-path',
          manifestRegistry.path,
          'list',
          '--json',
        ],
      );

      expect(result.exitCode, ExitCodes.success);
      final payload = jsonDecode(result.stdout) as Map<String, dynamic>;
      expect(payload['status'], 'ok');
      expect((payload['data'] as Map<String, dynamic>)['count'], 1);
    });

    test('theme help hides import flags unless advanced mode is enabled',
        () async {
      final normalHelp = await _runCli(
        cwd: appRoot.path,
        args: ['theme', '--help'],
      );
      final advancedHelp = await _runCli(
        cwd: appRoot.path,
        args: ['theme', '--advanced', '--help'],
      );

      expect(normalHelp.exitCode, ExitCodes.success);
      expect(normalHelp.stdout, isNot(contains('--apply-file')));
      expect(normalHelp.stdout, isNot(contains('--apply-url')));
      expect(advancedHelp.exitCode, ExitCodes.success);
      expect(advancedHelp.stdout, contains('--apply-file'));
      expect(advancedHelp.stdout, contains('--apply-url'));
    });

    test('theme --apply-file installs a declarative manifest in advanced mode',
        () async {
      final artifactFile = File(
        p.join(
          registryRoot.path,
          'shared',
          'theme',
          '_impl',
          'core',
          'generated_cli_theme.dart',
        ),
      )..createSync(recursive: true);
      artifactFile.writeAsStringSync(
        "const generatedCliTheme = 'cli-theme';\n",
      );
      final digest = sha256.convert(artifactFile.readAsBytesSync()).toString();

      final manifestFile = File(p.join(appRoot.path, 'cli-theme.json'))
        ..writeAsStringSync(
          jsonEncode({
            'id': 'cli-theme',
            'name': 'CLI Theme',
            'files': [
              {
                'source':
                    'registry/shared/theme/_impl/core/generated_cli_theme.dart',
                'target':
                    '{sharedPath}/theme/_impl/core/generated_cli_theme.dart',
                'sha256': digest,
              }
            ],
          }),
        );

      final result = await _runCli(
        cwd: appRoot.path,
        args: [
          '--advanced',
          '--offline',
          '--registry-path',
          registryRoot.path,
          'theme',
          '--apply-file',
          manifestFile.path,
        ],
      );

      expect(result.exitCode, ExitCodes.success);
      expect(
        File(
          p.join(
            appRoot.path,
            'lib',
            'ui',
            'shadcn',
            'shared',
            'theme',
            '_impl',
            'core',
            'generated_cli_theme.dart',
          ),
        ).existsSync(),
        isTrue,
      );
      final config = await ShadcnConfig.load(appRoot.path);
      expect(config.themeId, 'cli-theme');
    });

    test('theme --apply-file rejects raw preset payloads', () async {
      final payloadFile = File(p.join(appRoot.path, 'legacy-theme.json'))
        ..writeAsStringSync(
          jsonEncode({
            'id': 'legacy-theme',
            'light': {'primary': '0xFFFFFFFF'},
            'dark': {'primary': '0xFF000000'},
          }),
        );

      final result = await _runCli(
        cwd: appRoot.path,
        args: [
          '--advanced',
          '--offline',
          '--registry-path',
          registryRoot.path,
          'theme',
          '--apply-file',
          payloadFile.path,
        ],
      );

      expect(result.exitCode, ExitCodes.validationFailed);
      expect(result.stderr, contains('declarative theme manifest'));
    });

    test('developer registry override requires advanced mode', () async {
      final result = await _runCli(
        cwd: appRoot.path,
        args: [
          'list',
          '--registry-path',
          registryRoot.path,
        ],
      );

      expect(result.exitCode, ExitCodes.usage);
      expect(
          result.stderr, contains('--registry-path flag requires --advanced'));
    });

    test(
        'add namespace-qualified component works with older-shaped config/state',
        () async {
      File(p.join(appRoot.path, '.shadcn', 'config.json')).writeAsStringSync(
        jsonEncode({
          'registryMode': 'local',
          'registryPath': registryRoot.path,
          'installPath': 'lib/ui/shadcn',
          'sharedPath': 'lib/ui/shadcn/shared',
          'includeMeta': true,
        }),
      );
      File(p.join(appRoot.path, '.shadcn', 'state.json')).writeAsStringSync(
        jsonEncode({
          'installPath': 'lib/ui/shadcn',
          'sharedPath': 'lib/ui/shadcn/shared',
          'managedDependencies': ['gap']
        }),
      );

      await cli.main([
        'add',
        'shadcn:button',
      ]);

      final installFile = File(
        p.join(
          appRoot.path,
          'lib',
          'ui',
          'shadcn',
          'components',
          'button',
          'button.dart',
        ),
      );
      expect(installFile.existsSync(), isTrue);
      final normalizedState = jsonDecode(
        File(p.join(appRoot.path, '.shadcn', 'state.json')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(normalizedState['registries'], isA<Map>());
    });

    test('add @namespace/component installs from selected registry', () async {
      File(p.join(appRoot.path, '.shadcn', 'config.json')).writeAsStringSync(
        jsonEncode({
          'registryMode': 'local',
          'registryPath': registryRoot.path,
          'installPath': 'lib/ui/shadcn',
          'sharedPath': 'lib/ui/shadcn/shared',
          'includeMeta': true,
        }),
      );
      await cli.main([
        'add',
        '@shadcn/button',
      ]);

      final installFile = File(
        p.join(
          appRoot.path,
          'lib',
          'ui',
          'shadcn',
          'components',
          'button',
          'button.dart',
        ),
      );
      expect(installFile.existsSync(), isTrue);
    });

    test(
        'add --include-files=preview with @namespace installs preview and preview_state',
        () async {
      File(p.join(appRoot.path, '.shadcn', 'config.json')).writeAsStringSync(
        jsonEncode({
          'registryMode': 'local',
          'registryPath': registryRoot.path,
          'installPath': 'lib/ui/shadcn',
          'sharedPath': 'lib/ui/shadcn/shared',
          'includeMeta': true,
        }),
      );
      await cli.main([
        'add',
        '@shadcn/button',
        '--include-files=preview',
      ]);

      final installDir = p.join(
        appRoot.path,
        'lib',
        'ui',
        'shadcn',
        'components',
        'button',
      );
      expect(File(p.join(installDir, 'button.dart')).existsSync(), isTrue);
      expect(File(p.join(installDir, 'preview.dart')).existsSync(), isTrue);
      expect(
        File(p.join(installDir, 'preview_state.dart')).existsSync(),
        isTrue,
      );
      expect(File(p.join(installDir, 'meta.json')).existsSync(), isFalse);
      expect(File(p.join(installDir, 'README.md')).existsSync(), isFalse);
    });

    test('default command sets default namespace and registries list works',
        () async {
      final altRegistry = Directory(p.join(tempRoot.path, 'alt_registry'))
        ..createSync(recursive: true);
      _writeRegistryFixtures(altRegistry);

      File(p.join(appRoot.path, '.shadcn', 'config.json')).writeAsStringSync(
        jsonEncode({
          'defaultNamespace': 'shadcn',
          'registries': {
            'shadcn': {
              'registryMode': 'local',
              'registryPath': registryRoot.path,
              'installPath': 'lib/ui/shadcn',
              'sharedPath': 'lib/ui/shadcn/shared',
              'enabled': true
            },
            'alt': {
              'registryMode': 'local',
              'registryPath': altRegistry.path,
              'installPath': 'lib/ui/alt',
              'sharedPath': 'lib/ui/alt/shared',
              'enabled': true
            }
          }
        }),
      );

      await cli.main(['default', 'alt']);
      final config = jsonDecode(
        File(p.join(appRoot.path, '.shadcn', 'config.json')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(config['defaultNamespace'], 'alt');

      await cli.main(['registries', '--json', '--offline']);

      await cli.main(['add', '@alt/button']);
      expect(
        File(
          p.join(
            appRoot.path,
            'lib',
            'ui',
            'alt',
            'components',
            'button',
            'button.dart',
          ),
        ).existsSync(),
        isTrue,
      );
      final appComponents = File(
        p.join(appRoot.path, 'lib', 'ui', 'shadcn', 'app_components.dart'),
      );
      expect(appComponents.existsSync(), isTrue);
      final appComponentsSource = appComponents.readAsStringSync();
      expect(appComponentsSource,
          contains("export 'package:flutter/material.dart' hide"));
      expect(
          appComponentsSource, contains("export 'components/app/app.dart';"));
      expect(appComponentsSource, isNot(contains('typedef AppShadcnApp')));
    });

    test(
        'init namespace executes inline init actions from registries directory',
        () async {
      final fixture = jsonDecode(
        File(
          p.join(
            originalCwd.path,
            'test',
            'fixtures',
            'registry_inline_init_entry.json',
          ),
        ).readAsStringSync(),
      ) as Map<String, dynamic>;
      final registryEntry = Map<String, dynamic>.from(fixture);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        final path = request.uri.path;
        if (path == '/registries.json') {
          final entry = Map<String, dynamic>.from(registryEntry)
            ..['baseUrl'] = 'https://example.com/registry/'
            ..['paths'] = {
              'componentsJson': 'components.json',
              'componentsSchemaJson': 'components.schema.json'
            };
          request.response.write(
            jsonEncode({
              'schemaVersion': 1,
              'registries': [entry],
            }),
          );
          await request.response.close();
          return;
        }
        if (path == '/registry/shared/theme/color_scheme.dart') {
          request.response.write('class AppColorScheme {}');
          await request.response.close();
          return;
        }
        if (path == '/registry/components/index.json') {
          request.response.write(
            jsonEncode({
              'files': ['registry/components/button/button.dart'],
            }),
          );
          await request.response.close();
          return;
        }
        if (path == '/registry/components/button/button.dart') {
          request.response.write('class Button {}');
          await request.response.close();
          return;
        }
        if (path == '/components.json') {
          request.response.write(_emptyComponentsJson());
          await request.response.close();
          return;
        }
        if (path == '/components.schema.json') {
          request.response.write(jsonEncode({}));
          await request.response.close();
          return;
        }
        request.response.statusCode = 404;
        await request.response.close();
      });

      File(p.join(appRoot.path, '.shadcn', 'config.json')).writeAsStringSync(
        jsonEncode({
          'defaultNamespace': 'shadcn',
          'registries': {
            'shadcn': {
              'registryMode': 'remote',
              'registryUrl': 'http://${server.address.host}:${server.port}/',
              'baseUrl': 'http://${server.address.host}:${server.port}/',
              'installPath': 'lib/ui/shadcn',
              'sharedPath': 'lib/ui/shadcn/shared',
              'enabled': true
            }
          }
        }),
      );

      final registriesPath = _writeRegistriesFile(appRoot, [
        Map<String, dynamic>.from(registryEntry)
          ..['paths'] = {
            'componentsJson': 'components.json',
            'componentsSchemaJson': 'components.schema.json'
          },
      ]);

      await cli.main([
        '--advanced',
        'init',
        'shadcn',
        '--registries-path',
        registriesPath,
      ]);

      expect(
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
        ).existsSync(),
        isTrue,
      );
      expect(
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
        ).existsSync(),
        isTrue,
      );
    });

    test('init installs registry default components after inline actions',
        () async {
      final registriesPath = _writeRegistriesFile(appRoot, [
        {
          'id': 'shadcn_entry',
          'displayName': 'Shadcn',
          'maintainers': ['team'],
          'repo': 'https://example.com/repo',
          'license': 'MIT',
          'minCliVersion': '0.1.0',
          'baseUrl': 'https://example.com/registry/',
          'paths': {
            'componentsJson': 'components.json',
            'componentsSchemaJson': 'components.schema.json',
          },
          'install': {'namespace': 'shadcn', 'root': 'lib/ui/shadcn'},
          'init': {
            'version': 1,
            'defaultComponents': ['app'],
            'actions': [
              {
                'type': 'message',
                'lines': ['Init defaults ready'],
              }
            ],
          },
        }
      ]);

      final result = await _runCli(
        cwd: appRoot.path,
        args: [
          '--advanced',
          'init',
          'shadcn',
          '--yes',
          '--registries-path',
          registriesPath,
          '--registry-path',
          registryRoot.path,
        ],
      );

      expect(result.exitCode, ExitCodes.success);
      expect(
        File(
          p.join(
            appRoot.path,
            'lib',
            'ui',
            'shadcn',
            'components',
            'app',
            'app.dart',
          ),
        ).existsSync(),
        isTrue,
      );
      expect(
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
        ).existsSync(),
        isTrue,
      );
    });

    test(
        'init without namespace uses default namespace inline actions when registries are configured',
        () async {
      final fixture = jsonDecode(
        File(
          p.join(
            originalCwd.path,
            'test',
            'fixtures',
            'registry_inline_init_entry.json',
          ),
        ).readAsStringSync(),
      ) as Map<String, dynamic>;
      final registryEntry = Map<String, dynamic>.from(fixture);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        final path = request.uri.path;
        if (path == '/registries.json') {
          final entry = Map<String, dynamic>.from(registryEntry)
            ..['baseUrl'] = 'https://example.com/registry/'
            ..['paths'] = {
              'componentsJson': 'components.json',
              'componentsSchemaJson': 'components.schema.json'
            };
          request.response.write(
            jsonEncode({
              'schemaVersion': 1,
              'registries': [entry],
            }),
          );
          await request.response.close();
          return;
        }
        if (path == '/registry/shared/theme/color_scheme.dart') {
          request.response.write('class AppColorScheme {}');
          await request.response.close();
          return;
        }
        if (path == '/registry/components/index.json') {
          request.response.write(
            jsonEncode({
              'files': ['registry/components/button/button.dart'],
            }),
          );
          await request.response.close();
          return;
        }
        if (path == '/registry/components/button/button.dart') {
          request.response.write('class Button {}');
          await request.response.close();
          return;
        }
        if (path == '/components.json') {
          request.response.write(_emptyComponentsJson());
          await request.response.close();
          return;
        }
        if (path == '/components.schema.json') {
          request.response.write(jsonEncode({}));
          await request.response.close();
          return;
        }
        request.response.statusCode = 404;
        await request.response.close();
      });

      File(p.join(appRoot.path, '.shadcn', 'config.json')).writeAsStringSync(
        jsonEncode({
          'defaultNamespace': 'shadcn',
          'registries': {
            'shadcn': {
              'registryMode': 'remote',
              'registryUrl': 'http://${server.address.host}:${server.port}/',
              'baseUrl': 'http://${server.address.host}:${server.port}/',
              'installPath': 'lib/ui/shadcn',
              'sharedPath': 'lib/ui/shadcn/shared',
              'enabled': true
            }
          }
        }),
      );

      final registriesPath = _writeRegistriesFile(appRoot, [
        Map<String, dynamic>.from(registryEntry)
          ..['paths'] = {
            'componentsJson': 'components.json',
            'componentsSchemaJson': 'components.schema.json'
          },
      ]);

      await cli.main([
        '--advanced',
        'init',
        '--registries-path',
        registriesPath,
      ]);

      expect(
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
        ).existsSync(),
        isTrue,
      );
      expect(
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
        ).existsSync(),
        isTrue,
      );
    });

    test(
        'init without namespace bootstraps shadcn from registries directory on a clean project',
        () async {
      final fixture = jsonDecode(
        File(
          p.join(
            originalCwd.path,
            'test',
            'fixtures',
            'registry_inline_init_entry.json',
          ),
        ).readAsStringSync(),
      ) as Map<String, dynamic>;
      File(p.join(appRoot.path, '.shadcn', 'config.json')).deleteSync();
      File(
        p.join(
          registryRoot.path,
          'shared',
          'theme',
          'color_scheme.dart',
        ),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync('class AppColorScheme {}');
      File(
        p.join(registryRoot.path, 'components', 'index.json'),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'files': ['registry/components/button/button.dart'],
          }),
        );

      final registriesPath = _writeRegistriesFile(appRoot, [
        Map<String, dynamic>.from(fixture)
          ..['install'] = {
            ...((fixture['install'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{}),
            'namespace': 'shadcn',
          }
          ..['paths'] = {
            'componentsJson': 'components.json',
            'componentsSchemaJson': 'components.schema.json',
          },
      ]);

      await cli.main([
        '--advanced',
        '--offline',
        'init',
        '--yes',
        '--registries-path',
        registriesPath,
        '--registry-path',
        registryRoot.path,
      ]);
      expect(
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
        ).existsSync(),
        isTrue,
      );
      expect(
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
        ).existsSync(),
        isTrue,
      );
    });

    test('init without flags uses persisted local registry mode from config',
        () async {
      final fixture = jsonDecode(
        File(
          p.join(
            originalCwd.path,
            'test',
            'fixtures',
            'registry_inline_init_entry.json',
          ),
        ).readAsStringSync(),
      ) as Map<String, dynamic>;
      final registriesPath = _writeRegistriesFile(appRoot, [
        Map<String, dynamic>.from(fixture)
          ..['install'] = {
            ...((fixture['install'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{}),
            'namespace': 'shadcn',
          }
          ..['paths'] = {
            'componentsJson': 'components.json',
            'componentsSchemaJson': 'components.schema.json',
          },
      ]);

      File(
        p.join(registryRoot.path, 'shared', 'theme', 'color_scheme.dart'),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync('class AppColorScheme {}');
      File(
        p.join(registryRoot.path, 'components', 'index.json'),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'files': ['registry/components/button/button.dart'],
          }),
        );

      await ShadcnConfig.save(
        appRoot.path,
        ShadcnConfig(
          defaultNamespace: 'shadcn',
          registriesPath: registriesPath,
          registries: {
            'shadcn': RegistryConfigEntry(
              registryMode: 'local',
              registryPath: registryRoot.path,
              installPath: 'lib/ui/shadcn',
              sharedPath: 'lib/ui/shadcn/shared',
              enabled: true,
            ),
          },
        ),
      );

      await cli.main([
        '--advanced',
        '--offline',
        'init',
        '--yes',
      ]);

      expect(
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
        ).existsSync(),
        isTrue,
      );
      expect(
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
        ).existsSync(),
        isTrue,
      );
    });

    test(
        'registries schema accepts deprecated themeConverterDart path during directory load',
        () async {
      final fixture = jsonDecode(
        File(
          p.join(
            originalCwd.path,
            'test',
            'fixtures',
            'registry_inline_init_entry.json',
          ),
        ).readAsStringSync(),
      ) as Map<String, dynamic>;

      final registriesPath = _writeRegistriesFile(appRoot, [
        Map<String, dynamic>.from(fixture)
          ..['paths'] = {
            'componentsJson': 'components.json',
            'themeConverterDart':
                'https://example.com/tool/theme_converter.dart',
          },
      ]);

      final result = await _runCli(
        cwd: appRoot.path,
        args: [
          '--advanced',
          '--offline',
          'registries',
          '--registries-path',
          registriesPath,
          '--json',
        ],
      );

      expect(result.exitCode, ExitCodes.success);
      final payload = jsonDecode(result.stdout) as Map<String, dynamic>;
      expect(payload['status'], 'ok');
      expect(
        ((payload['data'] as Map<String, dynamic>)['items'] as List).length,
        1,
      );
    });

    test(
        'init consumes optional grouped actions from registries schema and derives assets from written files only',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        final path = request.uri.path;
        if (path == '/registries.json') {
          request.response.write(
            jsonEncode({
              'schemaVersion': 1,
              'registries': [
                {
                  'id': 'shadcn_entry',
                  'displayName': 'Shadcn',
                  'maintainers': ['team'],
                  'repo': 'https://example.com/repo',
                  'license': 'MIT',
                  'minCliVersion': '0.1.0',
                  'baseUrl': 'https://example.com/registry/',
                  'paths': {
                    'componentsJson': 'components.json',
                    'componentsSchemaJson': 'components.schema.json'
                  },
                  'install': {'namespace': 'shadcn', 'root': 'lib/ui/shadcn'},
                  'init': {
                    'version': 1,
                    'actions': [
                      {
                        'type': 'copyFiles',
                        'optional': true,
                        'promptLabel': 'Install shared assets?',
                        'promptDescription':
                            'Adds default shared assets for the registry.',
                        'base': 'registry',
                        'destBase': '.',
                        'from': 'shared',
                        'to': 'assets',
                        'groups': [
                          {
                            'label': 'Fonts',
                            'description': 'Font assets',
                            'default': true,
                            'files': ['fonts/typography_fonts.otf']
                          },
                          {
                            'label': 'Helpers',
                            'description': 'Dart helpers',
                            'default': false,
                            'files': ['theme/typography_fonts.dart']
                          }
                        ]
                      },
                      {
                        'type': 'mergePubspec',
                        'deriveFlutterAssets': true,
                      }
                    ]
                  }
                }
              ],
            }),
          );
          await request.response.close();
          return;
        }
        if (path == '/registry/shared/fonts/typography_fonts.otf') {
          request.response.write('font-bytes');
          await request.response.close();
          return;
        }
        if (path == '/registry/shared/theme/typography_fonts.dart') {
          request.response.write('class TypographyFonts {}');
          await request.response.close();
          return;
        }
        if (path == '/components.json') {
          request.response.write(_emptyComponentsJson());
          await request.response.close();
          return;
        }
        if (path == '/components.schema.json') {
          request.response.write(jsonEncode({}));
          await request.response.close();
          return;
        }
        request.response.statusCode = 404;
        await request.response.close();
      });

      File(p.join(appRoot.path, '.shadcn', 'config.json')).writeAsStringSync(
        jsonEncode({
          'defaultNamespace': 'shadcn',
          'registries': {
            'shadcn': {
              'registryMode': 'remote',
              'registryUrl': 'http://${server.address.host}:${server.port}/',
              'baseUrl': 'http://${server.address.host}:${server.port}/',
              'installPath': 'lib/ui/shadcn',
              'sharedPath': 'lib/ui/shadcn/shared',
              'enabled': true
            }
          }
        }),
      );

      final registriesPath = _writeRegistriesFile(appRoot, [
        {
          'id': 'shadcn_entry',
          'displayName': 'Shadcn',
          'maintainers': ['team'],
          'repo': 'https://example.com/repo',
          'license': 'MIT',
          'minCliVersion': '0.1.0',
          'baseUrl': 'https://example.com/registry/',
          'paths': {
            'componentsJson': 'components.json',
            'componentsSchemaJson': 'components.schema.json'
          },
          'install': {'namespace': 'shadcn', 'root': 'lib/ui/shadcn'},
          'init': {
            'version': 1,
            'actions': [
              {
                'type': 'copyFiles',
                'optional': true,
                'promptLabel': 'Install shared assets?',
                'promptDescription':
                    'Adds default shared assets for the registry.',
                'base': 'registry',
                'destBase': '.',
                'from': 'shared',
                'to': 'assets',
                'groups': [
                  {
                    'label': 'Fonts',
                    'description': 'Font assets',
                    'default': true,
                    'files': ['fonts/typography_fonts.otf']
                  },
                  {
                    'label': 'Helpers',
                    'description': 'Dart helpers',
                    'default': false,
                    'files': ['theme/typography_fonts.dart']
                  }
                ]
              },
              {
                'type': 'mergePubspec',
                'deriveFlutterAssets': true,
              }
            ]
          }
        }
      ]);

      final result = await _runCli(
        cwd: appRoot.path,
        args: [
          '--advanced',
          'init',
          'shadcn',
          '--yes',
          '--registries-path',
          registriesPath,
        ],
      );

      expect(result.exitCode, ExitCodes.success);
      expect(
        File(p.join(appRoot.path, 'assets', 'fonts', 'typography_fonts.otf'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(appRoot.path, 'assets', 'theme', 'typography_fonts.dart'))
            .existsSync(),
        isFalse,
      );
      final pubspec =
          File(p.join(appRoot.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('assets/fonts/typography_fonts.otf'));
      expect(pubspec, isNot(contains('assets/theme/typography_fonts.dart')));
    });

    test('assets and remove use inline registry actions when available',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      server.listen((request) async {
        final path = request.uri.path;
        if (path == '/registries.json') {
          request.response.write(
            jsonEncode({
              'schemaVersion': 1,
              'registries': [
                {
                  'id': 'shadcn_entry',
                  'displayName': 'Shadcn',
                  'maintainers': ['team'],
                  'repo': 'https://example.com/repo',
                  'license': 'MIT',
                  'minCliVersion': '0.1.0',
                  'baseUrl': 'https://example.com/registry/',
                  'paths': {
                    'componentsJson': 'components.json',
                    'componentsSchemaJson': 'components.schema.json'
                  },
                  'install': {'namespace': 'shadcn', 'root': 'lib/ui/shadcn'},
                  'init': {
                    'version': 1,
                    'actions': [
                      {
                        'type': 'ensureDirs',
                        'dirs': ['assets/fonts']
                      },
                      {
                        'type': 'copyFiles',
                        'base': 'registry',
                        'destBase': 'lib/ui/shadcn',
                        'files': ['registry/shared/fonts/typography_fonts.dart']
                      },
                      {
                        'type': 'mergePubspec',
                        'dependencies': {'google_fonts': '^6.2.1'},
                        'flutterAssets': ['assets/fonts/GeistSans-Regular.ttf'],
                        'flutterFonts': [
                          {
                            'family': 'GeistSans',
                            'fonts': [
                              {
                                'asset': 'assets/fonts/GeistSans-Regular.ttf',
                                'weight': 400
                              }
                            ]
                          }
                        ]
                      }
                    ]
                  }
                }
              ]
            }),
          );
          await request.response.close();
          return;
        }
        if (path == '/components.json') {
          request.response.write(
            jsonEncode({
              'schemaVersion': 1,
              'name': 'inline_assets',
              'flutter': {'minSdk': '3.0.0'},
              'defaults': {
                'installPath': 'lib/ui/shadcn',
                'sharedPath': 'lib/ui/shadcn/shared',
              },
              'shared': [],
              'components': [],
            }),
          );
          await request.response.close();
          return;
        }
        if (path == '/components.schema.json') {
          request.response.write(jsonEncode({}));
          await request.response.close();
          return;
        }
        if (path == '/registry/shared/fonts/typography_fonts.dart') {
          request.response.write('class TypographyFonts {}');
          await request.response.close();
          return;
        }
        request.response.statusCode = 404;
        await request.response.close();
      });

      File(p.join(appRoot.path, '.shadcn', 'config.json')).writeAsStringSync(
        jsonEncode({
          'defaultNamespace': 'shadcn',
          'registries': {
            'shadcn': {
              'registryMode': 'remote',
              'registryUrl': 'http://${server.address.host}:${server.port}/',
              'baseUrl': 'http://${server.address.host}:${server.port}/',
              'installPath': 'lib/ui/shadcn',
              'sharedPath': 'lib/ui/shadcn/shared',
              'enabled': true
            }
          }
        }),
      );

      final registriesPath = _writeRegistriesFile(appRoot, [
        {
          'id': 'shadcn_entry',
          'displayName': 'Shadcn',
          'maintainers': ['team'],
          'repo': 'https://example.com/repo',
          'license': 'MIT',
          'minCliVersion': '0.1.0',
          'baseUrl': 'https://example.com/registry/',
          'paths': {
            'componentsJson': 'components.json',
            'componentsSchemaJson': 'components.schema.json'
          },
          'install': {'namespace': 'shadcn', 'root': 'lib/ui/shadcn'},
          'init': {
            'version': 1,
            'actions': [
              {
                'type': 'ensureDirs',
                'dirs': ['assets/fonts']
              },
              {
                'type': 'copyFiles',
                'base': 'registry',
                'destBase': 'lib/ui/shadcn',
                'files': ['registry/shared/fonts/typography_fonts.dart']
              },
              {
                'type': 'mergePubspec',
                'dependencies': {'google_fonts': '^6.2.1'},
                'flutterAssets': ['assets/fonts/GeistSans-Regular.ttf'],
                'flutterFonts': [
                  {
                    'family': 'GeistSans',
                    'fonts': [
                      {
                        'asset': 'assets/fonts/GeistSans-Regular.ttf',
                        'weight': 400
                      }
                    ]
                  }
                ]
              }
            ]
          }
        }
      ]);

      await cli.main([
        '--advanced',
        'assets',
        '--typography',
        '--registries-path',
        registriesPath,
      ]);
      expect(
        File(
          p.join(
            appRoot.path,
            'lib',
            'ui',
            'shadcn',
            'shared',
            'fonts',
            'typography_fonts.dart',
          ),
        ).existsSync(),
        isTrue,
      );

      await cli.main([
        '--advanced',
        'remove',
        'typography_fonts',
        '--registries-path',
        registriesPath,
      ]);
      expect(
        File(
          p.join(
            appRoot.path,
            'lib',
            'ui',
            'shadcn',
            'shared',
            'fonts',
            'typography_fonts.dart',
          ),
        ).existsSync(),
        isFalse,
      );
    });

    test('assets fails instead of installing removed asset component fallback',
        () async {
      File(p.join(appRoot.path, '.shadcn', 'config.json')).writeAsStringSync(
        jsonEncode({
          'defaultNamespace': 'shadcn',
          'registries': {
            'shadcn': {
              'registryMode': 'local',
              'registryPath': registryRoot.path,
              'installPath': 'lib/ui/shadcn',
              'sharedPath': 'lib/ui/shadcn/shared',
              'enabled': true
            }
          }
        }),
      );

      final registriesPath = _writeRegistriesFile(appRoot, [
        {
          'id': 'shadcn_entry',
          'displayName': 'Shadcn',
          'maintainers': ['team'],
          'repo': 'https://example.com/repo',
          'license': 'MIT',
          'minCliVersion': '0.1.0',
          'baseUrl': 'https://example.com/registry/',
          'paths': {
            'componentsJson': 'components.json',
            'componentsSchemaJson': 'components.schema.json'
          },
          'install': {'namespace': 'shadcn', 'root': 'lib/ui/shadcn'},
        }
      ]);

      final result = await _runCli(
        cwd: appRoot.path,
        args: [
          '--advanced',
          'assets',
          '--typography',
          '--registries-path',
          registriesPath,
        ],
      );

      expect(result.exitCode, isNot(ExitCodes.success));
      expect(result.stderr, contains('inline registry actions'));
      expect(
        File(
          p.join(
            appRoot.path,
            'lib',
            'ui',
            'shadcn',
            'components',
            'typography_fonts',
            'typography_fonts.dart',
          ),
        ).existsSync(),
        isFalse,
      );
    });

    test('rejects registry path and registry url overrides together', () async {
      final result = await _runCli(
        cwd: appRoot.path,
        args: [
          '--advanced',
          '--registry-path',
          registryRoot.path,
          '--registry-url',
          'https://example.com/registry/',
          'add',
          'button',
        ],
      );

      expect(result.exitCode, ExitCodes.usage);
      expect(
        result.stderr,
        contains('--registry-path and --registry-url cannot be used together'),
      );
    });

    test('add exits schema invalid when components schema fails', () async {
      final invalidRegistry =
          Directory(p.join(tempRoot.path, 'invalid_add_schema'))
            ..createSync(recursive: true);
      _writeRegistryFixtures(invalidRegistry);
      _writeSchemaRequiringBlockedField(invalidRegistry);

      final result = await _runCli(
        cwd: appRoot.path,
        args: [
          '--advanced',
          '--offline',
          '--registry-path',
          invalidRegistry.path,
          'add',
          'button',
        ],
      );

      expect(result.exitCode, ExitCodes.schemaInvalid);
      expect(result.stderr, contains('schema validation failed'));
    });

    test('add bypasses invalid components schema with skip integrity',
        () async {
      final invalidRegistry =
          Directory(p.join(tempRoot.path, 'invalid_add_schema_bypass'))
            ..createSync(recursive: true);
      _writeRegistryFixtures(invalidRegistry);
      _writeSchemaRequiringBlockedField(invalidRegistry);

      final result = await _runCli(
        cwd: appRoot.path,
        args: [
          '--advanced',
          '--offline',
          '--skip-integrity',
          '--registry-path',
          invalidRegistry.path,
          'add',
          'button',
        ],
      );

      expect(result.exitCode, ExitCodes.success);
      expect(
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
        ).existsSync(),
        isTrue,
      );
    });

    test('init exits schema invalid when components schema fails', () async {
      final invalidRegistry =
          Directory(p.join(tempRoot.path, 'invalid_init_schema'))
            ..createSync(recursive: true);
      _writeRegistryFixtures(invalidRegistry);
      _writeSchemaRequiringBlockedField(invalidRegistry);
      final registriesFile = _writeRegistriesFile(appRoot, [
        {
          'id': 'broken_entry',
          'displayName': 'Broken',
          'maintainers': ['team'],
          'repo': 'https://example.com/repo',
          'license': 'MIT',
          'minCliVersion': '0.1.0',
          'baseUrl': 'https://example.com/registry/',
          'paths': {
            'componentsJson': 'components.json',
            'componentsSchemaJson': 'components.schema.json'
          },
          'install': {'namespace': 'broken', 'root': 'lib/ui/broken'},
        },
      ]);

      final result = await _runCli(
        cwd: appRoot.path,
        args: [
          '--advanced',
          '--offline',
          '--registries-path',
          registriesFile,
          '--registry-path',
          invalidRegistry.path,
          'init',
          'broken',
          '--yes',
        ],
      );

      expect(result.exitCode, ExitCodes.schemaInvalid);
      expect(result.stderr, contains('schema validation failed'));
    });

    test('preloaded commands map schema failures to schema invalid', () async {
      final invalidRegistry =
          Directory(p.join(tempRoot.path, 'invalid_preload_schema'))
            ..createSync(recursive: true);
      _writeRegistryFixtures(invalidRegistry);
      _writeSchemaRequiringBlockedField(invalidRegistry);

      final result = await _runCli(
        cwd: appRoot.path,
        args: [
          '--advanced',
          '--offline',
          '--registry-path',
          invalidRegistry.path,
          'validate',
        ],
      );

      expect(result.exitCode, ExitCodes.schemaInvalid);
      expect(result.stderr, contains('schema validation failed'));
    });

    test('validate reports schema failures', () async {
      final invalidRegistry =
          Directory(p.join(tempRoot.path, 'invalid_registry'))
            ..createSync(recursive: true);
      File(p.join(invalidRegistry.path, 'components.json'))
          .writeAsStringSync('{"schemaVersion":1}');

      final result = await _runCli(
        cwd: appRoot.path,
        args: [
          '--advanced',
          'validate',
          '--registry-path',
          invalidRegistry.path,
        ],
      );

      expect(result.exitCode, ExitCodes.schemaInvalid);
      expect(result.stderr, contains('schema validation failed'));
    });

    test('sync preserves component manifests', () async {
      await cli.main([
        '--advanced',
        '--offline',
        'add',
        'button',
        '--registry-path',
        registryRoot.path,
      ]);

      await cli.main([
        'sync',
      ]);

      final manifestFile = File(
        p.join(appRoot.path, '.shadcn', 'components', 'button.json'),
      );
      expect(manifestFile.existsSync(), isTrue);
    });

    test('offline list uses cached index', () async {
      exitCode = 0;
      final registryUrl = 'https://example.com/registry';
      final registryId =
          registryUrl.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          tempRoot.path;
      final cacheDir = Directory(
        p.join(home, '.flutter_shadcn', 'cache', registryId),
      );
      cacheDir.createSync(recursive: true);
      File(p.join(cacheDir.path, 'index.json')).writeAsStringSync(
        jsonEncode({'components': []}),
      );

      await cli.main([
        '--advanced',
        'list',
        '--registry-url',
        registryUrl,
        '--offline',
        '--json',
      ]);

      expect(exitCode, ExitCodes.success);
    });

    test('default command accepts --registries-path for local registries.json',
        () async {
      final localRegistriesFile =
          File(p.join(appRoot.path, 'dev_registry', 'registries.json'))
            ..createSync(recursive: true);
      localRegistriesFile.writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'registries': [
            {
              'id': 'local_dev',
              'displayName': 'Local Dev',
              'maintainers': ['team'],
              'repo': 'https://github.com/example/local-dev',
              'license': 'MIT',
              'minCliVersion': '0.1.0',
              'baseUrl': 'https://example.com/local-dev/',
              'paths': {
                'componentsJson': 'components.json',
                'componentsSchemaJson': 'components.schema.json'
              },
              'install': {'namespace': 'localdev', 'root': 'lib/ui/localdev'}
            }
          ]
        }),
      );

      await cli.main([
        '--advanced',
        'default',
        'localdev',
        '--registries-path',
        localRegistriesFile.path,
      ]);

      final updated = await ShadcnConfig.load(appRoot.path);
      final entry = updated.registryConfig('localdev');
      expect(updated.effectiveDefaultNamespace, 'localdev');
      expect(entry, isNotNull);
      expect(entry?.baseUrl, 'https://example.com/local-dev/');
      expect(entry?.installPath, 'lib/ui/localdev');
    });

    test('list/search accept @namespace registry token', () async {
      exitCode = 0;
      final badRemote = 'http://127.0.0.1:9/unreachable/';
      File(p.join(appRoot.path, '.shadcn', 'config.json')).writeAsStringSync(
        jsonEncode({
          'defaultNamespace': 'orient_ui',
          'registries': {
            'shadcn': {
              'registryMode': 'local',
              'registryPath': registryRoot.path,
              'installPath': 'lib/ui/shadcn',
              'sharedPath': 'lib/ui/shadcn/shared',
              'enabled': true
            },
            'orient_ui': {
              'registryMode': 'remote',
              'registryUrl': badRemote,
              'baseUrl': badRemote,
              'enabled': true
            }
          }
        }),
      );

      await cli.main(['list', '@shadcn', '--json']);
      expect(exitCode, ExitCodes.success);

      exitCode = 0;
      await cli.main(['search', '@shadcn', 'button', '--json']);
      expect(exitCode, ExitCodes.success);
    });

    test('theme widget commands fail explicitly without runtime execution',
        () async {
      _writeWidgetThemeHostFiles(appRoot, 'lib/ui/shadcn');

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
                'sha256':
                    '0000000000000000000000000000000000000000000000000000000000000000',
              }
            ],
          }),
        );

      final result = await _runCli(
        cwd: appRoot.path,
        args: [
          '--advanced',
          '--offline',
          '--registry-path',
          registryRoot.path,
          'theme',
          '@shadcn',
          'widget',
          'button',
          '--apply-file',
          payloadFile.path,
        ],
      );
      expect(result.exitCode, ExitCodes.validationFailed);
      expect(result.stderr, contains('experimental'));

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
        contains("const buttonThemeTarget = '__BUTTON_THEME_TARGET__';"),
      );
    });

    test('init without --yes still completes with default config', () async {
      final registriesPath = _writeRegistriesFile(appRoot, [
        {
          'id': 'shadcn_entry',
          'displayName': 'Shadcn',
          'maintainers': ['team'],
          'repo': 'https://example.com/repo',
          'license': 'MIT',
          'minCliVersion': '0.1.0',
          'baseUrl': 'https://example.com/registry/',
          'paths': {
            'componentsJson': 'components.json',
            'componentsSchemaJson': 'components.schema.json',
          },
          'install': {'namespace': 'shadcn', 'root': 'lib/ui/shadcn'},
          'init': {
            'version': 1,
            'actions': [
              {
                'type': 'message',
                'lines': ['Init done'],
              }
            ],
          },
        },
      ]);

      File(p.join(appRoot.path, '.shadcn', 'config.json')).deleteSync();

      await cli.main([
        '--advanced',
        '--offline',
        'init',
        '--registries-path',
        registriesPath,
        '--registry-path',
        registryRoot.path,
      ]);

      final config = File(p.join(appRoot.path, '.shadcn', 'config.json'));
      expect(config.existsSync(), isTrue);
      expect(
        config.readAsStringSync(),
        contains('"installPath":"lib/ui/shadcn"'),
      );
    });
  });
}

void _writeRegistryFixtures(Directory registryRoot) {
  final root = p.dirname(registryRoot.path);
  final componentsDir =
      Directory(p.join(root, 'registry', 'components', 'button'))
        ..createSync(recursive: true);
  final appDir = Directory(p.join(root, 'registry', 'components', 'app'))
    ..createSync(recursive: true);
  final dialogDir = Directory(p.join(root, 'registry', 'components', 'dialog'))
    ..createSync(recursive: true);
  final sharedThemeDir = Directory(p.join(root, 'registry', 'shared', 'theme'))
    ..createSync(recursive: true);
  final sharedUtilDir = Directory(p.join(root, 'registry', 'shared', 'util'))
    ..createSync(recursive: true);
  final sharedColorExtensionsDir =
      Directory(p.join(root, 'registry', 'shared', 'color_extensions'))
        ..createSync(recursive: true);
  final sharedFormControlDir =
      Directory(p.join(root, 'registry', 'shared', 'form_control'))
        ..createSync(recursive: true);
  final sharedFormValueSupplierDir =
      Directory(p.join(root, 'registry', 'shared', 'form_value_supplier'))
        ..createSync(recursive: true);
  final typographyDir =
      Directory(p.join(root, 'registry', 'components', 'typography_fonts'))
        ..createSync(recursive: true);
  final iconDir =
      Directory(p.join(root, 'registry', 'components', 'icon_fonts'))
        ..createSync(recursive: true);

  File(p.join(componentsDir.path, 'button.dart'))
      .writeAsStringSync('class Button {}');
  File(p.join(componentsDir.path, 'README.md')).writeAsStringSync('# Button');
  File(p.join(componentsDir.path, 'meta.json'))
      .writeAsStringSync('{"id":"button"}');
  File(p.join(componentsDir.path, 'preview.dart'))
      .writeAsStringSync('class ButtonPreview {}');
  File(p.join(componentsDir.path, 'preview_state.dart'))
      .writeAsStringSync('class ButtonPreviewState {}');

  File(p.join(appDir.path, 'app.dart')).writeAsStringSync('class ShadcnApp {}');
  File(p.join(appDir.path, 'meta.json')).writeAsStringSync('{"id":"app"}');

  File(p.join(dialogDir.path, 'dialog.dart'))
      .writeAsStringSync('class Dialog {}');
  File(p.join(dialogDir.path, 'meta.json'))
      .writeAsStringSync('{"id":"dialog"}');

  File(p.join(sharedThemeDir.path, 'theme.dart'))
      .writeAsStringSync('class ThemeHelper {}');
  File(p.join(sharedUtilDir.path, 'util.dart'))
      .writeAsStringSync('class UtilHelper {}');
  File(p.join(sharedColorExtensionsDir.path, 'color_extensions.dart'))
      .writeAsStringSync('class ColorExtensions {}');
  File(p.join(sharedFormControlDir.path, 'form_control.dart'))
      .writeAsStringSync('class FormControl {}');
  File(p.join(sharedFormValueSupplierDir.path, 'form_value_supplier.dart'))
      .writeAsStringSync('class FormValueSupplier {}');

  File(p.join(typographyDir.path, 'typography_fonts.dart'))
      .writeAsStringSync('class TypographyFonts {}');
  File(p.join(typographyDir.path, 'meta.json'))
      .writeAsStringSync('{"id":"typography_fonts"}');
  File(p.join(iconDir.path, 'icon_fonts.dart'))
      .writeAsStringSync('class IconFonts {}');
  File(p.join(iconDir.path, 'meta.json'))
      .writeAsStringSync('{"id":"icon_fonts"}');

  final registryJson = {
    'schemaVersion': 1,
    'name': 'test_registry',
    'flutter': {'minSdk': '>=3.3.0'},
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
      },
      {
        'id': 'util',
        'files': [
          {
            'source': 'registry/shared/util/util.dart',
            'destination': '{sharedPath}/util/util.dart'
          }
        ]
      },
      {
        'id': 'color_extensions',
        'files': [
          {
            'source': 'registry/shared/color_extensions/color_extensions.dart',
            'destination': '{sharedPath}/color_extensions/color_extensions.dart'
          }
        ]
      },
      {
        'id': 'form_control',
        'files': [
          {
            'source': 'registry/shared/form_control/form_control.dart',
            'destination': '{sharedPath}/form_control/form_control.dart'
          }
        ]
      },
      {
        'id': 'form_value_supplier',
        'files': [
          {
            'source':
                'registry/shared/form_value_supplier/form_value_supplier.dart',
            'destination':
                '{sharedPath}/form_value_supplier/form_value_supplier.dart'
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
        'files': [
          {
            'source': 'registry/components/button/button.dart',
            'destination': '{installPath}/components/button/button.dart',
            'dependsOn': ['registry/shared/theme/theme.dart']
          },
          {
            'source': 'registry/components/button/meta.json',
            'destination': '{installPath}/components/button/meta.json'
          },
          {
            'source': 'registry/components/button/README.md',
            'destination': '{installPath}/components/button/README.md'
          },
          {
            'source': 'registry/components/button/preview.dart',
            'destination': '{installPath}/components/button/preview.dart'
          },
          {
            'source': 'registry/components/button/preview_state.dart',
            'destination': '{installPath}/components/button/preview_state.dart'
          }
        ],
        'shared': ['theme'],
        'dependsOn': [],
        'pubspec': {'dependencies': {}},
        'assets': [],
        'postInstall': []
      },
      {
        'id': 'app',
        'name': 'App',
        'description': 'App shell',
        'category': 'layout',
        'version': '1.0.0',
        'tags': ['app'],
        'files': [
          {
            'source': 'registry/components/app/app.dart',
            'destination': '{installPath}/components/app/app.dart'
          },
          {
            'source': 'registry/components/app/meta.json',
            'destination': '{installPath}/components/app/meta.json'
          }
        ],
        'shared': ['theme'],
        'dependsOn': ['button'],
        'pubspec': {'dependencies': {}},
        'assets': [],
        'postInstall': []
      },
      {
        'id': 'dialog',
        'name': 'Dialog',
        'description': 'Dialog component',
        'category': 'overlay',
        'version': '0.1.0',
        'tags': ['overlay'],
        'files': [
          {
            'source': 'registry/components/dialog/dialog.dart',
            'destination': '{installPath}/components/dialog/dialog.dart'
          },
          {
            'source': 'registry/components/dialog/meta.json',
            'destination': '{installPath}/components/dialog/meta.json'
          }
        ],
        'shared': [],
        'dependsOn': ['button'],
        'pubspec': {'dependencies': {}},
        'assets': [],
        'postInstall': []
      },
      {
        'id': 'typography_fonts',
        'name': 'Typography Fonts',
        'description': 'Typography font assets',
        'category': 'utility',
        'version': '1.0.0',
        'tags': ['assets'],
        'files': [
          {
            'source':
                'registry/components/typography_fonts/typography_fonts.dart',
            'destination':
                '{installPath}/components/typography_fonts/typography_fonts.dart'
          },
          {
            'source': 'registry/components/typography_fonts/meta.json',
            'destination': '{installPath}/components/typography_fonts/meta.json'
          }
        ],
        'shared': [],
        'dependsOn': [],
        'pubspec': {'dependencies': {}},
        'assets': [],
        'postInstall': []
      },
      {
        'id': 'icon_fonts',
        'name': 'Icon Fonts',
        'description': 'Icon font assets',
        'category': 'utility',
        'version': '1.0.0',
        'tags': ['assets'],
        'files': [
          {
            'source': 'registry/components/icon_fonts/icon_fonts.dart',
            'destination': '{installPath}/components/icon_fonts/icon_fonts.dart'
          },
          {
            'source': 'registry/components/icon_fonts/meta.json',
            'destination': '{installPath}/components/icon_fonts/meta.json'
          }
        ],
        'shared': [],
        'dependsOn': [],
        'pubspec': {'dependencies': {}},
        'assets': [],
        'postInstall': []
      }
    ]
  };

  File(p.join(registryRoot.path, 'components.json')).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(registryJson));
  File(p.join(registryRoot.path, 'components.schema.json'))
      .writeAsStringSync(jsonEncode({}));
  File(p.join(registryRoot.path, 'index.json')).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'components': [
        {
          'id': 'button',
          'name': 'Button',
          'category': 'control',
          'description': 'Button component',
          'tags': ['core'],
          'install': 'flutter_shadcn add button',
          'import': 'package:app/ui/shadcn/components/button/button.dart',
          'importPath': 'ui/shadcn/components/button/button.dart',
          'api': {},
          'examples': {},
          'dependencies': {},
          'related': ['dialog']
        },
        {
          'id': 'dialog',
          'name': 'Dialog',
          'category': 'overlay',
          'description': 'Dialog component',
          'tags': ['overlay'],
          'install': 'flutter_shadcn add dialog',
          'import': 'package:app/ui/shadcn/components/dialog/dialog.dart',
          'importPath': 'ui/shadcn/components/dialog/dialog.dart',
          'api': {},
          'examples': {},
          'dependencies': {},
          'related': ['button']
        }
      ]
    }),
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

Future<Map<String, dynamic>> _loadSource(Map<String, dynamic> source) async {
  final type = source['type']?.toString();
  if (type == 'file') {
    final path = source['path']?.toString();
    if (path == null || path.isEmpty) {
      throw Exception('Missing file source path.');
    }
    return jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
  }
  if (type == 'url') {
    final rawUrl = source['url']?.toString();
    if (rawUrl == null || rawUrl.isEmpty) {
      throw Exception('Missing URL source.');
    }
    final uri = Uri.parse(rawUrl);
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to fetch widget theme URL (${response.statusCode}).');
      }
      final content = await response.transform(utf8.decoder).join();
      return jsonDecode(content) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }
  throw Exception('Unsupported source type: $type');
}

Future<void> main(List<String> args) async {
  final request = jsonDecode(await File(args.first).readAsString())
      as Map<String, dynamic>;
  if (request['scope'] != 'widget') {
    stdout.write(jsonEncode({'scope': request['scope'], 'installPlan': {'operations': []}}));
    return;
  }

  final action = request['action']?.toString() ?? 'apply';
  final componentId = request['componentId']?.toString() ?? '';
  final namespace = request['namespace']?.toString() ?? '';
  final context = request['context'] as Map<String, dynamic>? ?? const {};
  final installPath = context['installPath']?.toString() ?? '';
  final payloadFile = request['payloadFile']?.toString() ?? '';
  final hostPath = joinPath(
    joinPath(joinPath(installPath, 'components'), componentId),
    'button_theme_host.dart',
  );
  final generatedPath = joinPath(
    joinPath(joinPath(installPath, 'components'), componentId),
    'generated_${namespace}_theme.dart',
  );

  if (action == 'reset') {
    stdout.write(jsonEncode({
      'scope': 'widget',
      'resolvedNamespace': namespace,
      'resolvedComponent': componentId,
      'resolvedTargetThemeType': 'PrimaryButtonTheme',
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

  final payload = jsonDecode(await File(payloadFile).readAsString())
      as Map<String, dynamic>;
  final selectedTarget =
      payload['targetThemeType']?.toString() ?? 'PrimaryButtonTheme';
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
          'content': "const active${componentId}Theme = '${selectedTarget}';\n",
        }
      ]
    }
  }));
}
''');
}

String _writeRegistriesFile(
  Directory appRoot,
  List<Map<String, dynamic>> entries,
) {
  final file = File(p.join(appRoot.path, 'registries.json'));
  file.writeAsStringSync(
    jsonEncode({
      'schemaVersion': 1,
      'registries': entries,
    }),
  );
  return file.path;
}

String _emptyComponentsJson() {
  return jsonEncode({
    'schemaVersion': 1,
    'name': 'inline_registry',
    'defaults': {
      'installPath': 'lib/ui/shadcn',
      'sharedPath': 'lib/ui/shadcn/shared',
    },
    'components': [],
  });
}

void _writeSchemaRequiringBlockedField(Directory registryRoot) {
  File(p.join(registryRoot.path, 'components.schema.json')).writeAsStringSync(
    jsonEncode({
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      'type': 'object',
      'required': ['blockedField'],
      'properties': {
        'blockedField': {'type': 'string'},
      },
    }),
  );
}

Future<ProcessResult> _runCli({
  required String cwd,
  required List<String> args,
}) {
  return Process.run(
    Platform.resolvedExecutable,
    [_cliEntrypoint, ...args],
    workingDirectory: cwd,
    environment: {
      ...Platform.environment,
      'CI': 'true',
    },
  );
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
