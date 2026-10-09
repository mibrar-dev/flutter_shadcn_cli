import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_schema_validator.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:path/path.dart' as p;
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

  group('valid fixture', () {
    test('passes validation', () {
      final result = ManifestSchemaValidator.validate(clone());
      expect(result.isValid, isTrue, reason: result.errors.join('\n'));
    });

    test('passes validation with a materialized registry root', () {
      final root = Directory.systemTemp.createTempSync('registry_v2_');
      addTearDown(() => root.delete(recursive: true));
      final manifest = RegistryManifest.fromJson(valid);
      for (final file in manifest.declaredFiles) {
        final target = File(p.join(root.path, file));
        target.parent.createSync(recursive: true);
        target.writeAsStringSync('// fixture\n');
      }
      final result = ManifestSchemaValidator.validate(
        clone(),
        registryRoot: root.path,
      );
      expect(result.isValid, isTrue, reason: result.errors.join('\n'));
    });

    test('rejects a missing file on disk when registryRoot is given', () {
      final root = Directory.systemTemp.createTempSync('registry_v2_');
      addTearDown(() => root.delete(recursive: true));
      final manifest = RegistryManifest.fromJson(valid);
      final files = manifest.declaredFiles.toList()
        ..remove('foundation/gap.dart');
      for (final file in files) {
        final target = File(p.join(root.path, file));
        target.parent.createSync(recursive: true);
        target.writeAsStringSync('// fixture\n');
      }
      final result = ManifestSchemaValidator.validate(
        clone(),
        registryRoot: root.path,
      );
      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('foundation/gap.dart')));
    });
  });

  group('schemaVersion', () {
    test('rejects a version other than 2', () {
      final data = clone()..['schemaVersion'] = 1;
      final result = ManifestSchemaValidator.validate(data);
      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('schemaVersion must be 2')));
    });

    test('rejects a string version', () {
      final data = clone()..['schemaVersion'] = '2';
      expect(ManifestSchemaValidator.validate(data).isValid, isFalse);
    });
  });

  group('top-level shape', () {
    test('rejects a missing required key', () {
      final data = clone()..remove('themes');
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('themes')));
    });

    test('rejects an unknown key', () {
      final data = clone()..['extra'] = true;
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('extra')));
    });

    test('allows the optional \$schema key', () {
      expect(ManifestSchemaValidator.validate(clone()).isValid, isTrue);
    });
  });

  group('registry and install blocks', () {
    test('rejects an empty registry name', () {
      final data = clone();
      (data['registry'] as Map<String, dynamic>)['name'] = '';
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('registry.name')));
    });

    test('rejects a wrong install.componentsDir', () {
      final data = clone();
      (data['install'] as Map<String, dynamic>)['componentsDir'] = 'ui';
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('componentsDir')));
    });

    test('rejects a wrong install.userOwnedSuffix', () {
      final data = clone();
      (data['install'] as Map<String, dynamic>)['userOwnedSuffix'] =
          '_style.dart';
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('userOwnedSuffix')));
    });

    test('rejects a missing install layer dir', () {
      final data = clone();
      ((data['install'] as Map<String, dynamic>)['layerDirs']
              as Map<String, dynamic>)
          .remove('theme');
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('layerDirs')));
    });
  });

  group('ids and relPaths', () {
    test('rejects an invalid unit id', () {
      final data = clone();
      final foundation = data['foundation'] as Map<String, dynamic>;
      final gap = foundation.remove('gap')!;
      foundation['Gap!'] = gap;
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('invalid unit id')));
    });

    test('rejects a relPath with a backslash', () {
      final data = clone();
      updateUnit(data, 'foundation', 'data', (unit) {
        unit['files'] = ['foundation\\data.dart'];
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('forward slashes')));
    });

    test('rejects a relPath with a leading ./', () {
      final data = clone();
      updateUnit(data, 'primitives', 'clickable', (unit) {
        unit['files'] = ['./primitives/clickable.dart'];
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('invalid relPath')));
    });

    test('rejects a relPath escaping the layer dir', () {
      final data = clone();
      updateUnit(data, 'foundation', 'data', (unit) {
        unit['files'] = ['primitives/data.dart'];
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('not under foundation/')));
    });

    test('rejects a duplicate files entry', () {
      final data = clone();
      updateUnit(data, 'theme', 'theme', (unit) {
        unit['files'] = ['theme/theme.dart', 'theme/theme.dart'];
      });
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('duplicate entry')));
    });

    test('rejects an invalid sha256 format', () {
      final data = clone();
      (data['fileHashes'] as Map<String, dynamic>)['foundation/data.dart'] =
          'ABC123';
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('sha256')));
    });

    test('rejects a fileHashes entry missing for a declared file', () {
      final data = clone();
      (data['fileHashes'] as Map<String, dynamic>).remove(
        'foundation/gap.dart',
      );
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('missing entry')));
    });
  });
}
