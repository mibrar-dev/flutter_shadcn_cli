import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry/index_loader.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry/theme_index_entry.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry/theme_index_loader.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry/theme_preset_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Index and theme loaders', () {
    test('IndexLoader resolves configured indexPath', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      var requestedPath = '';
      server.listen((request) async {
        requestedPath = request.uri.path;
        if (request.uri.path == '/registry/manifests/index.json') {
          request.response.statusCode = 200;
          request.response.write(
            jsonEncode({
              'components': [
                {
                  'id': 'button',
                  'name': 'Button',
                  'category': 'control',
                  'description': 'Button',
                }
              ],
            }),
          );
          await request.response.close();
          return;
        }
        request.response.statusCode = 404;
        await request.response.close();
      });

      final loader = IndexLoader(
        registryId: 'index_loader_path_test',
        registryBaseUrl:
            'http://${server.address.host}:${server.port}/registry',
        indexPath: 'manifests/index.json',
        refresh: true,
      );

      final data = await loader.load();
      expect((data['components'] as List).length, 1);
      expect(requestedPath, '/registry/manifests/index.json');
    });

    test('ThemeIndexLoader loads and parses theme entries', () async {
      final temp = Directory.systemTemp.createTempSync('theme_index_loader_');
      addTearDown(() {
        if (temp.existsSync()) {
          temp.deleteSync(recursive: true);
        }
      });

      final indexFile = File(
        p.join(temp.path, 'registry', 'manifests', 'theme.index.json'),
      )..createSync(recursive: true);
      indexFile.writeAsStringSync(
        jsonEncode({
          'themes': [
            {
              'id': 'amber-minimal',
              'name': 'Amber Minimal',
              'files': [
                {
                  'source':
                      'shared/theme/generated/amber-minimal/preset_themes.dart',
                  'target': '{sharedPath}/theme/preset_themes.dart',
                  'sha256': 'a' * 64,
                }
              ],
            }
          ]
        }),
      );

      final loader = ThemeIndexLoader(
        registryId: 'theme_index_loader_test',
        registryBaseUrl: temp.path,
        themesPath: 'registry/manifests/theme.index.json',
        offline: true,
      );

      final data = await loader.load();
      final entries = loader.entriesFrom(data);
      expect(entries.length, 1);
      expect(entries.first.id, 'amber-minimal');
      expect(entries.first.file, isEmpty);
      expect(entries.first.files.single['target'],
          '{sharedPath}/theme/preset_themes.dart');
    });

    test('ThemePresetLoader reads declarative file entries from theme index',
        () async {
      final loader = ThemePresetLoader(
        registryId: 'theme_preset_index_entry_test',
        registryBaseUrl: Directory.systemTemp.path,
        themesPath: 'registry/manifests/theme.index.json',
      );

      final manifest = await loader.loadManifest(
        ThemeIndexEntry(
          id: 'amber-minimal',
          name: 'Amber Minimal',
          files: [
            {
              'source':
                  'shared/theme/generated/amber-minimal/preset_themes.dart',
              'target': '{sharedPath}/theme/preset_themes.dart',
              'sha256': 'b' * 64,
            },
            {
              'source':
                  'shared/theme/generated/amber-minimal/app_theme_preset.dart',
              'target': '{sharedPath}/theme/app_theme_preset.dart',
              'sha256': 'c' * 64,
            },
          ],
        ),
      );

      expect(manifest.id, 'amber-minimal');
      expect(manifest.name, 'Amber Minimal');
      expect(manifest.files, hasLength(2));
      expect(manifest.files.last.source, contains('app_theme_preset.dart'));
      expect(manifest.files.last.sha256, 'c' * 64);
    });

    test(
        'ThemePresetLoader loads declarative theme manifests and caches artifacts',
        () async {
      final temp = Directory.systemTemp.createTempSync('theme_preset_loader_');
      addTearDown(() {
        if (temp.existsSync()) {
          temp.deleteSync(recursive: true);
        }
      });

      final artifactFile = File(
        p.join(
          temp.path,
          'registry',
          'shared',
          'theme',
          '_impl',
          'core',
          'custom_theme.dart',
        ),
      )..createSync(recursive: true);
      artifactFile.writeAsStringSync(
        'const customThemeName = "Custom Theme";\n',
      );
      final artifactBytes = artifactFile.readAsBytesSync();
      final digest = sha256.convert(artifactBytes).toString();

      final manifestFile = File(
        p.join(
          temp.path,
          'registry',
          'manifests',
          'themes_preset',
          'custom-theme.json',
        ),
      )..createSync(recursive: true);
      manifestFile.writeAsStringSync(
        jsonEncode({
          'id': 'custom-theme',
          'name': 'Custom Theme',
          'files': [
            {
              'source': 'registry/shared/theme/_impl/core/custom_theme.dart',
              'target':
                  'lib/ui/shadcn/shared/theme/_impl/core/custom_theme.dart',
              'sha256': digest,
            }
          ],
        }),
      );

      final loader = ThemePresetLoader(
        registryId: 'theme_preset_loader_test',
        registryBaseUrl: temp.path,
        themesPath: 'registry/manifests/theme.index.json',
      );

      final manifest = await loader.loadManifest(
        const ThemeIndexEntry(
          id: 'custom-theme',
          name: 'Custom Theme',
          file: 'themes_preset/custom-theme.json',
        ),
      );
      final artifacts = await loader.cacheArtifacts(manifest);

      expect(manifest.id, 'custom-theme');
      expect(manifest.name, 'Custom Theme');
      expect(manifest.files, hasLength(1));
      expect(
        manifest.files.single.target,
        'lib/ui/shadcn/shared/theme/_impl/core/custom_theme.dart',
      );
      expect(manifest.files.single.sha256, digest);
      expect(artifacts, hasLength(1));
      expect(artifacts.single.bytes, artifactBytes);
      expect(artifacts.single.cacheFile.existsSync(), isTrue);
      expect(loader.verifySha256(artifactBytes, digest), isTrue);
      expect(loader.verifySha256(artifactBytes, '0' * 64), isFalse);
    });

    test('ThemePresetLoader revalidates cached artifacts before reuse',
        () async {
      final temp = Directory.systemTemp.createTempSync('theme_preset_cache_');
      addTearDown(() {
        if (temp.existsSync()) {
          temp.deleteSync(recursive: true);
        }
      });

      final artifactFile = File(
        p.join(
          temp.path,
          'registry',
          'shared',
          'theme',
          '_impl',
          'core',
          'validated_theme.dart',
        ),
      )..createSync(recursive: true);
      artifactFile.writeAsStringSync(
        'const validatedThemeName = "Validated Theme";\n',
      );
      final artifactBytes = artifactFile.readAsBytesSync();
      final digest = sha256.convert(artifactBytes).toString();

      final manifestFile = File(
        p.join(
          temp.path,
          'registry',
          'manifests',
          'themes_preset',
          'validated-theme.json',
        ),
      )..createSync(recursive: true);
      manifestFile.writeAsStringSync(
        jsonEncode({
          'id': 'validated-theme',
          'name': 'Validated Theme',
          'files': [
            {
              'source': 'registry/shared/theme/_impl/core/validated_theme.dart',
              'target':
                  'lib/ui/shadcn/shared/theme/_impl/core/validated_theme.dart',
              'sha256': digest,
            }
          ],
        }),
      );

      final loader = ThemePresetLoader(
        registryId: 'theme_preset_loader_cache_validation_test',
        registryBaseUrl: temp.path,
        themesPath: 'registry/manifests/theme.index.json',
        cacheRootPath: p.join(temp.path, '.cache'),
      );

      final manifest = await loader.loadManifest(
        const ThemeIndexEntry(
          id: 'validated-theme',
          name: 'Validated Theme',
          file: 'themes_preset/validated-theme.json',
        ),
      );
      final initialArtifacts = await loader.cacheArtifacts(manifest);
      expect(initialArtifacts.single.bytes, artifactBytes);

      initialArtifacts.single.cacheFile.writeAsStringSync(
        'corrupted cache contents\n',
        flush: true,
      );

      final reloadedArtifacts = await loader.cacheArtifacts(manifest);
      expect(reloadedArtifacts.single.bytes, artifactBytes);
      expect(
          reloadedArtifacts.single.cacheFile.readAsBytesSync(), artifactBytes);
    });
  });
}
