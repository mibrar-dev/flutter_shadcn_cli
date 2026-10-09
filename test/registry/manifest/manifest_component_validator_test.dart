import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_schema_validator.dart';
import 'package:test/test.dart';

void main() {
  late Map<String, dynamic> valid;

  setUpAll(() {
    valid = jsonDecode(
      File('test/fixtures/registry_v2/registry.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  Map<String, dynamic> clone() =>
      jsonDecode(jsonEncode(valid)) as Map<String, dynamic>;

  /// Replaces `data['components'][id]` with a copy transformed by [body].
  void updateComponent(
    Map<String, dynamic> data,
    String id,
    void Function(Map<String, dynamic> component) body,
  ) {
    final components = data['components'] as Map<String, dynamic>;
    final component = Map<String, dynamic>.from(
      components[id] as Map<String, dynamic>,
    );
    body(component);
    components[id] = component;
  }

  /// Replaces `data['<group>'][id]` with a copy transformed by [body].
  void updateUnit(
    Map<String, dynamic> data,
    String group,
    String id,
    void Function(Map<String, dynamic> unit) body,
  ) {
    final units = data[group] as Map<String, dynamic>;
    final unit = Map<String, dynamic>.from(
      units[id] as Map<String, dynamic>,
    );
    body(unit);
    units[id] = unit;
  }

  group('component shape', () {
    test('rejects a component entry with an id key (map key is the id)', () {
      final data = clone();
      updateComponent(data, 'button', (component) {
        component['id'] = 'btn';
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('unknown key "id"')));
    });

    test('rejects an unknown component key', () {
      final data = clone();
      updateComponent(data, 'button', (component) {
        component['namespace'] = 'ui';
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('unknown key "namespace"')));
    });

    test('rejects an entry outside the component directory', () {
      final data = clone();
      updateComponent(data, 'button', (component) {
        component['entry'] = 'components/btn/button.dart';
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('entry')));
    });

    test('rejects preview.dart listed in files', () {
      final data = clone();
      updateComponent(data, 'button', (component) {
        component['files'] = [
          'components/button/button.dart',
          'components/button/preview.dart',
        ];
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('preview.dart')));
    });

    test('rejects a file listed in both files and userOwned', () {
      final data = clone();
      updateComponent(data, 'button', (component) {
        component['userOwned'] = ['components/button/button_style.dart'];
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('both files and userOwned')));
    });

    test('rejects a userOwned file not ending in _theme.dart', () {
      final data = clone();
      updateComponent(data, 'button', (component) {
        component['userOwned'] = ['components/button/button_style.dart'];
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('_theme.dart')));
    });

    test('rejects a duplicate tag', () {
      final data = clone();
      updateComponent(data, 'button', (component) {
        component['tags'] = ['control', 'control'];
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('duplicate tag')));
    });

    test('rejects a malformed api block', () {
      final data = clone();
      updateComponent(data, 'button', (component) {
        component['api'] = {'classes': 'Button'};
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('api')));
    });
  });

  group('deps closure', () {
    test('rejects an unknown component deps key', () {
      final data = clone();
      updateComponent(data, 'button', (component) {
        component['deps'] = {
          'foundation': ['data', 'gap'],
          'theme': ['theme', 'color_tokens'],
          'primitives': ['clickable'],
          'components': <String>[],
          'assets': <String>[],
        };
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('unknown key "assets"')));
    });

    test('rejects a missing component deps key', () {
      final data = clone();
      updateComponent(data, 'button', (component) {
        component['deps'] = {
          'foundation': ['data', 'gap'],
          'theme': ['theme', 'color_tokens'],
          'primitives': ['clickable'],
        };
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('missing required key')));
    });

    test('rejects a component dep on a missing component', () {
      final data = clone();
      updateComponent(data, 'text_area', (component) {
        component['deps'] = {
          'foundation': ['data'],
          'theme': ['theme'],
          'primitives': ['form_core'],
          'components': ['input', 'missing'],
        };
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(
        result.errors,
        contains(contains('unknown component id "missing"')),
      );
    });

    test('rejects a component dep on a missing primitive', () {
      final data = clone();
      updateComponent(data, 'button', (component) {
        component['deps'] = {
          'foundation': ['data', 'gap'],
          'theme': ['theme', 'color_tokens'],
          'primitives': ['clickable', 'missing'],
          'components': <String>[],
        };
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(
        result.errors,
        contains(contains('unknown primitive id "missing"')),
      );
    });

    test('rejects a component dep on a missing foundation unit', () {
      final data = clone();
      updateComponent(data, 'button', (component) {
        component['deps'] = {
          'foundation': ['data', 'gap', 'missing'],
          'theme': ['theme', 'color_tokens'],
          'primitives': ['clickable'],
          'components': <String>[],
        };
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(
        result.errors,
        contains(contains('unknown foundation id "missing"')),
      );
    });

    test('rejects a primitive dep on a missing primitive', () {
      final data = clone();
      updateUnit(data, 'primitives', 'form_core', (unit) {
        unit['deps'] = {
          'primitives': ['clickable', 'missing'],
        };
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(
        result.errors,
        contains(contains('unknown primitive id "missing"')),
      );
    });

    test('rejects an unknown primitive deps key', () {
      final data = clone();
      updateUnit(data, 'primitives', 'form_core', (unit) {
        unit['deps'] = {
          'primitives': ['clickable'],
          'foundation': ['data'],
        };
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('unknown key "foundation"')));
    });

    test('accepts a primitive dependency cycle (plan §9.7)', () {
      final data = clone();
      updateUnit(data, 'primitives', 'clickable', (unit) {
        unit['deps'] = {
          'primitives': ['form_core'],
        };
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('still rejects a primitive dep on a missing primitive', () {
      final data = clone();
      updateUnit(data, 'primitives', 'clickable', (unit) {
        unit['deps'] = {
          'primitives': ['form_core', 'missing'],
        };
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(
        result.errors,
        contains(contains('unknown primitive id "missing"')),
      );
    });
  });

  group('theme presets', () {
    test('rejects an invalid mode', () {
      final data = clone();
      (data['themes'] as Map<String, dynamic>)['modern-minimal'] = {
        'file': 'themes/modern-minimal.json',
        'name': 'Modern Minimal',
        'modes': ['light', 'sepia'],
      };
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('invalid mode')));
    });

    test('rejects an empty modes list', () {
      final data = clone();
      (data['themes'] as Map<String, dynamic>)['modern-minimal'] = {
        'file': 'themes/modern-minimal.json',
        'name': 'Modern Minimal',
        'modes': <String>[],
      };
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('modes')));
    });

    test('rejects a preset file outside themes/', () {
      final data = clone();
      (data['themes'] as Map<String, dynamic>)['modern-minimal'] = {
        'file': 'presets/modern-minimal.json',
        'name': 'Modern Minimal',
        'modes': ['light', 'dark'],
      };
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('themes/')));
    });
  });

  group('packages', () {
    test('rejects a package entry without a name', () {
      final data = clone();
      updateComponent(data, 'button', (component) {
        component['packages'] = [
          {'sdk': true},
        ];
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('packages.name')));
    });

    test('rejects a non-boolean sdk flag', () {
      final data = clone();
      updateComponent(data, 'button', (component) {
        component['packages'] = [
          {'name': 'intl', 'sdk': 'yes'},
        ];
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('packages.sdk')));
    });
  });
}
