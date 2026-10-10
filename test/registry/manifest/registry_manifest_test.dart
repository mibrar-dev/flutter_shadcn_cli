import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_unit.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:test/test.dart';

void main() {
  late Map<String, dynamic> json;

  setUpAll(() {
    final content = File(
      'test/fixtures/registry_v2/registry.json',
    ).readAsStringSync();
    json = jsonDecode(content) as Map<String, dynamic>;
  });

  group('RegistryManifest.fromJson', () {
    test('parses top-level blocks', () {
      final manifest = RegistryManifest.fromJson(json);
      expect(manifest.schemaVersion, 2);
      expect(manifest.registry.name, 'shadcn_flutter');
      expect(manifest.registry.version, '0.2.7');
      expect(manifest.registry.ref, 'refactor/rearchitecture');
      expect(manifest.registry.generatedAt, '2026-10-09T00:00:00Z');
      expect(manifest.install.root, 'lib/ui/shadcn');
      expect(manifest.install.componentsDir, 'components');
      expect(manifest.install.layerDirs.foundation, 'foundation');
      expect(manifest.install.layerDirs.theme, 'theme');
      expect(manifest.install.layerDirs.primitives, 'primitives');
      expect(manifest.install.userOwnedSuffix, '_theme.dart');
    });

    test('parses layer units keyed by id', () {
      final manifest = RegistryManifest.fromJson(json);
      expect(manifest.foundation.keys, ['data', 'gap']);
      expect(manifest.foundation['data']!.files, ['foundation/data.dart']);
      expect(manifest.theme.keys, ['theme', 'color_tokens']);
      expect(
        manifest.theme['color_tokens']!.files,
        ['theme/color_tokens.dart', 'theme/color_utils.dart'],
      );
      expect(manifest.primitives.keys, ['clickable', 'form_core']);
    });

    test('parses primitive files and primitive-to-primitive deps', () {
      final manifest = RegistryManifest.fromJson(json);
      expect(manifest.primitives['clickable']!.deps.primitives, isEmpty);
      expect(
        manifest.primitives['form_core']!.files,
        ['primitives/form_core/form_core.dart'],
      );
      expect(manifest.primitives['form_core']!.deps.primitives, ['clickable']);
    });

    test('parses a component with deps, api, theme and packages', () {
      final manifest = RegistryManifest.fromJson(json);
      final button = manifest.components['button']!;
      expect(button.name, 'Button');
      expect(button.category, 'control');
      expect(button.description, isNotEmpty);
      expect(button.entry, 'components/button/button.dart');
      expect(button.files, [
        'components/button/button.dart',
        'components/button/button_style.dart',
      ]);
      expect(button.userOwned, ['components/button/button_theme.dart']);
      expect(button.deps.foundation, ['data', 'gap']);
      expect(button.deps.theme, ['theme', 'color_tokens']);
      expect(button.deps.primitives, ['clickable']);
      expect(button.deps.components, isEmpty);
      expect(button.tags, ['control', 'button']);
      expect(
        button.api.symbolNames,
        containsAll(['Button', 'ButtonGroup', 'ButtonVariant', 'ButtonSize']),
      );
      expect(button.theme!.className, 'ButtonTheme');
      expect(button.theme!.userFile, 'button_theme.dart');
      expect(button.theme!.extra['fields'], isA<Map<String, dynamic>>());
      expect(button.install, 'flutter_shadcn add button');
      expect(button.import, contains('components/button/button.dart'));
      expect(button.packages.single.name, 'intl');
      expect(button.packages.single.constraint, '^0.20.2');
      expect(button.packages.single.sdk, isFalse);
    });

    test('parses component-to-component dep and absent/null themes', () {
      final manifest = RegistryManifest.fromJson(json);
      final textArea = manifest.components['text_area']!;
      expect(textArea.deps.components, ['input']);
      expect(textArea.userOwned, isEmpty);
      expect(textArea.deps.primitives, ['form_core']);
      expect(textArea.theme, isNull);
      expect(manifest.components['input']!.theme, isNull);
      expect(manifest.components['input']!.userOwned, isEmpty);
    });

    test('parses theme presets and file hashes', () {
      final manifest = RegistryManifest.fromJson(json);
      final preset = manifest.themes['modern-minimal']!;
      expect(preset.file, 'themes/modern-minimal.json');
      expect(preset.name, 'Modern Minimal');
      expect(preset.modes, ['light', 'dark']);
      expect(manifest.fileHashes.length, 19);
      expect(manifest.fileHashes['foundation/data.dart'], isNotEmpty);
    });

    test('declaredFiles is the union of unit, component and preset files', () {
      final manifest = RegistryManifest.fromJson(json);
      final declared = manifest.declaredFiles;
      expect(
        declared,
        containsAll([
          'foundation/data.dart',
          'foundation/gap.dart',
          'theme/color_utils.dart',
          'primitives/clickable.dart',
          'primitives/form_core/form_core.dart',
          'components/button/button_theme.dart',
          'components/text_area/text_area.dart',
          'blocks/login-01/login_01.dart',
          'blocks/dashboard-01/dashboard_01.dart',
          'blocks/dashboard-01/dashboard_01_table.dart',
          'themes/modern-minimal.json',
        ]),
      );
      // 16 copyable registry files: 5 layer + 6 component + 3 block + preset...
      // (the component user-owned file and the preset JSON make up the rest).
      expect(declared.length, 16);
      // A block's docs are never copied into an app.
      expect(declared, isNot(contains('blocks/login-01/README.md')));
    });

    test('tolerates missing optional blocks', () {
      final manifest = RegistryManifest.fromJson(const {'schemaVersion': 2});
      expect(manifest.schemaVersion, 2);
      expect(manifest.registry.name, isEmpty);
      expect(manifest.components, isEmpty);
      expect(manifest.fileHashes, isEmpty);
      expect(manifest.declaredFiles, isEmpty);
    });
  });

  group('PackageRef', () {
    test('parses sdk flag and constraint', () {
      final ref = PackageRef.fromJson(const {
        'name': 'flutter_localizations',
        'sdk': true,
      });
      expect(ref.name, 'flutter_localizations');
      expect(ref.sdk, isTrue);
      expect(ref.constraint, isNull);
    });

    test('listFromJson returns empty for non-list input', () {
      expect(PackageRef.listFromJson(null), isEmpty);
      expect(PackageRef.listFromJson(const []), isEmpty);
    });
  });
}
