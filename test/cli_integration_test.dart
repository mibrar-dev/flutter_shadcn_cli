import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/shadcn.dart' as cli;
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';

void main() {
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
      Directory.current = originalCwd;
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('add installs component and writes manifests', () async {
      await cli.main([
        'add',
        'button',
        '--registry',
        'local',
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
      expect(
          aliasFile.readAsStringSync().contains('typedef AppButton = Button;'),
          isTrue);
    });

    test('doctor runs without crashing', () async {
      await cli.main([
        'doctor',
        '--registry',
        'local',
        '--registry-path',
        registryRoot.path,
      ]);
    });

    test('init installs positional components', () async {
      await cli.main([
        'init',
        '--yes',
        'button',
        'dialog',
        '--registry',
        'local',
        '--registry-path',
        registryRoot.path,
      ]);

      final buttonFile = File(
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
      final dialogFile = File(
        p.join(
          appRoot.path,
          'lib',
          'ui',
          'shadcn',
          'components',
          'dialog',
          'dialog.dart',
        ),
      );

      expect(buttonFile.existsSync(), isTrue);
      expect(dialogFile.existsSync(), isTrue);
    });

    test('init installs typography fonts when requested', () async {
      await cli.main([
        'init',
        '--yes',
        '--install-fonts',
        '--registry',
        'local',
        '--registry-path',
        registryRoot.path,
      ]);

      final typographyFile = File(
        p.join(
          appRoot.path,
          'lib',
          'ui',
          'shadcn',
          'components',
          'typography_fonts',
          'typography_fonts.dart',
        ),
      );
      expect(typographyFile.existsSync(), isTrue);
    });

    test('add namespace-qualified component works with legacy config/state',
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
      final migratedState = jsonDecode(
        File(p.join(appRoot.path, '.shadcn', 'state.json')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(migratedState['registries'], isA<Map>());
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

      await cli.main(['add', 'button']);
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
            ..['paths'] = {'componentsJson': 'components.json'};
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

      await cli.main([
        'init',
        'shadcn',
        '--registries-url',
        'http://${server.address.host}:${server.port}/registries.json',
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
            ..['paths'] = {'componentsJson': 'components.json'};
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

      await cli.main([
        'init',
        '--registries-url',
        'http://${server.address.host}:${server.port}/registries.json',
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
                  'paths': {'componentsJson': 'components.json'},
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

      await cli.main([
        'assets',
        '--typography',
        '--registries-url',
        'http://${server.address.host}:${server.port}/registries.json',
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
        'remove',
        'typography_fonts',
        '--registries-url',
        'http://${server.address.host}:${server.port}/registries.json',
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

    test('validate reports schema failures', () async {
      exitCode = 0;
      final invalidRegistry =
          Directory(p.join(tempRoot.path, 'invalid_registry'))
            ..createSync(recursive: true);
      File(p.join(invalidRegistry.path, 'components.json'))
          .writeAsStringSync('{"schemaVersion":1}');

      await cli.main([
        'validate',
        '--registry',
        'local',
        '--registry-path',
        invalidRegistry.path,
      ]);

      expect(exitCode, ExitCodes.schemaInvalid);
    });

    test('sync preserves component manifests', () async {
      await cli.main([
        'add',
        'button',
        '--registry',
        'local',
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
        'list',
        '--registry',
        'remote',
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
              'paths': {'componentsJson': 'components.json'},
              'install': {'namespace': 'localdev', 'root': 'lib/ui/localdev'}
            }
          ]
        }),
      );

      await cli.main([
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

    test('theme widget apply/reset is namespace-aware', () async {
      _writeWidgetThemeHostFiles(appRoot, 'lib/ui/shadcn');
      _writeWidgetThemeHostFiles(appRoot, 'lib/ui/alt');

      final payloadFile = File(p.join(appRoot.path, 'button_theme.json'))
        ..writeAsStringSync(jsonEncode({'target': 'PrimaryButtonTheme'}));

      File(p.join(appRoot.path, '.shadcn', 'config.json')).writeAsStringSync(
        jsonEncode({
          'defaultNamespace': 'shadcn',
          'registries': {
            'shadcn': {
              'registryMode': 'local',
              'registryPath': registryRoot.path,
              'installPath': 'lib/ui/shadcn',
              'sharedPath': 'lib/ui/shadcn/shared',
              'widgetThemesPath': 'registry/manifests/widget_theme.index.json',
              'themeConverterDartPath':
                  'registry/manifests/theme_converter.dart',
              'enabled': true
            },
            'alt': {
              'registryMode': 'local',
              'registryPath': registryRoot.path,
              'installPath': 'lib/ui/alt',
              'sharedPath': 'lib/ui/alt/shared',
              'widgetThemesPath': 'registry/manifests/widget_theme.index.json',
              'themeConverterDartPath':
                  'registry/manifests/theme_converter.dart',
              'enabled': true
            }
          }
        }),
      );

      await cli.main([
        'theme',
        '@shadcn',
        'widget',
        'button',
        '--apply-file',
        payloadFile.path,
      ]);
      expect(exitCode, ExitCodes.success);

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

      exitCode = 0;
      await cli.main([
        'theme',
        '@alt',
        'widget',
        'button',
        '--apply-file',
        payloadFile.path,
      ]);
      expect(exitCode, ExitCodes.success);
      expect(
        altHost.readAsStringSync(),
        contains("const buttonThemeTarget = 'PrimaryButtonTheme';"),
      );

      exitCode = 0;
      await cli.main([
        'theme',
        '@alt',
        'widget',
        'button',
        '--reset',
      ]);
      expect(exitCode, ExitCodes.success);
      expect(
        altHost.readAsStringSync(),
        contains("const buttonThemeTarget = '__BUTTON_THEME_TARGET__';"),
      );
      expect(
        shadcnHost.readAsStringSync(),
        contains("const buttonThemeTarget = 'PrimaryButtonTheme';"),
      );
    });
  });
}

void _writeRegistryFixtures(Directory registryRoot) {
  final root = p.dirname(registryRoot.path);
  final componentsDir =
      Directory(p.join(root, 'registry', 'components', 'button'))
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

  final widgetThemeIndex = File(
    p.join(registryRoot.path, 'manifests', 'widget_theme.index.json'),
  )..createSync(recursive: true);
  widgetThemeIndex.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'components': [
        {
          'componentId': 'button',
          'label': 'Button',
          'defaultTarget': 'PrimaryButtonTheme',
          'targets': [
            {
              'id': 'PrimaryButtonTheme',
              'label': 'Primary',
              'default': true,
              'schemaPath':
                  'registry/components/control/button/registry/theme.schema.json',
              'configPath':
                  'registry/components/control/button/_impl/themes/config/button_theme_config.dart'
            }
          ]
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
  final registrySourceRoot = context['registrySourceRoot']?.toString() ?? '';
  final widgetThemesPath = context['widgetThemesPath']?.toString() ?? '';

  final manifestFile = File(joinPath(registrySourceRoot, widgetThemesPath));
  final manifest = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
  final components = (manifest['components'] as List? ?? const [])
      .whereType<Map>()
      .map((entry) => entry.map((key, value) => MapEntry(key.toString(), value)))
      .toList();
  final component = components.firstWhere(
    (entry) => entry['componentId'] == componentId || entry['id'] == componentId,
  );
  final target = component['defaultTarget']?.toString() ?? 'global';
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
      'resolvedTargetThemeType': target,
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

  final source = request['source'] as Map<String, dynamic>? ?? const {};
  final payload = await _loadSource(source);
  final selectedTarget = payload['target']?.toString() ?? target;
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
          'replace': source['type']?.toString() ?? 'unknown',
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
