import 'dart:convert';
import 'dart:io';

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
              'file': 'themes_preset/amber-minimal.json',
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
      expect(entries.first.file, 'themes_preset/amber-minimal.json');
    });

    test('ThemePresetLoader supports registry converter dart script', () async {
      final temp = Directory.systemTemp.createTempSync('theme_preset_loader_');
      addTearDown(() {
        if (temp.existsSync()) {
          temp.deleteSync(recursive: true);
        }
      });

      final presetFile = File(
        p.join(
          temp.path,
          'registry',
          'manifests',
          'themes_preset',
          'custom-theme.json',
        ),
      )..createSync(recursive: true);
      presetFile.writeAsStringSync(
        jsonEncode({
          'theme_id': 'custom-theme',
          'theme_name': 'Custom Theme',
          'tokens': {
            'light': {'primary': '#ffffff'},
            'dark': {'primary': '#000000'},
          }
        }),
      );

      final converter = File(
        p.join(temp.path, 'registry', 'manifests', 'theme_converter.dart'),
      )..createSync(recursive: true);
      converter.writeAsStringSync('''
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final input = jsonDecode(await File(args.first).readAsString()) as Map<String, dynamic>;
  final tokens = input['tokens'] as Map<String, dynamic>;
  final output = {
    'id': input['theme_id'],
    'name': input['theme_name'],
    'light': (tokens['light'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
    'dark': (tokens['dark'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
  };
  stdout.write(jsonEncode(output));
}
''');

      final loader = ThemePresetLoader(
        registryId: 'theme_preset_loader_test',
        registryBaseUrl: temp.path,
        themesPath: 'registry/manifests/theme.index.json',
        themeConverterDartPath: 'registry/manifests/theme_converter.dart',
      );

      final preset = await loader.loadPreset(
        const ThemeIndexEntry(
          id: 'custom-theme',
          name: 'Custom Theme',
          file: 'themes_preset/custom-theme.json',
        ),
      );

      expect(preset.id, 'custom-theme');
      expect(preset.name, 'Custom Theme');
      expect(preset.light['primary'], '#ffffff');
      expect(preset.dark['primary'], '#000000');
    });
  });
}
