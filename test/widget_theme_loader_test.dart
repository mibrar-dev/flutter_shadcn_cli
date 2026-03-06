import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/infrastructure/registry/widget_theme_index_loader.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Widget theme index loader', () {
    test('loads and parses widget theme entries', () async {
      final temp = Directory.systemTemp.createTempSync('widget_theme_loader_');
      addTearDown(() {
        if (temp.existsSync()) {
          temp.deleteSync(recursive: true);
        }
      });

      final indexFile = File(
        p.join(temp.path, 'registry', 'manifests', 'widget_theme.index.json'),
      )..createSync(recursive: true);
      indexFile.writeAsStringSync(
        jsonEncode({
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
                      'registry/components/control/button/_impl/themes/config/button_theme_config.dart',
                }
              ],
            }
          ]
        }),
      );

      final loader = WidgetThemeIndexLoader(
        registryId: 'widget_theme_loader_test',
        registryBaseUrl: temp.path,
        widgetThemesPath: 'registry/manifests/widget_theme.index.json',
        offline: true,
      );

      final data = await loader.load();
      final entries = loader.entriesFrom(data);
      expect(entries, hasLength(1));
      expect(entries.first.componentId, 'button');
      expect(entries.first.defaultTarget, 'PrimaryButtonTheme');
      expect(entries.first.targets, hasLength(1));
      expect(entries.first.targets.first.id, 'PrimaryButtonTheme');
      expect(entries.first.targets.first.isDefault, isTrue);
    });
  });
}
