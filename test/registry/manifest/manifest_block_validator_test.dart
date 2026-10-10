import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_schema_validator.dart';
import 'package:flutter_shadcn_cli/src/registry/schema_validation_result.dart';
import 'package:test/test.dart';

/// The `blocks` map of a v2 manifest (P6-B1 layer 4) as the CLI validates it.
///
/// Every case starts from the checked-in fixture, which carries two blocks:
/// `login-01` (one Dart file, desktop) and `dashboard-01` (two Dart files,
/// mobile).
void main() {
  late Map<String, dynamic> valid;

  setUpAll(() {
    valid = jsonDecode(
      File('test/fixtures/registry_v2/registry.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  Map<String, dynamic> clone() =>
      jsonDecode(jsonEncode(valid)) as Map<String, dynamic>;

  Map<String, dynamic> block(String id) =>
      (clone()['blocks'] as Map<String, dynamic>)[id] as Map<String, dynamic>;

  SchemaValidationResult validate(Map<String, dynamic> data) =>
      ManifestSchemaValidator.validate(data);

  group('valid blocks', () {
    test('the fixture with both blocks passes', () {
      final result = validate(clone());
      expect(result.isValid, isTrue, reason: result.errors.join('\n'));
    });

    test('a manifest with no blocks key is still valid', () {
      final result = validate(clone()..remove('blocks'));
      expect(result.isValid, isTrue, reason: result.errors.join('\n'));
    });

    test('blocks install.blocksDir is accepted', () {
      final data = clone();
      (data['install'] as Map<String, dynamic>)['blocksDir'] = 'blocks';
      expect(validate(data).isValid, isTrue);
    });
  });

  group('block shape', () {
    test('rejects an unknown key', () {
      final data = clone();
      (data['blocks'] as Map<String, dynamic>)['login-01'] = {
        ...block('login-01'),
        'api': {
          'classes': ['Login01']
        },
      };
      expect(
        validate(data).errors,
        contains(contains('blocks.login-01: unknown key "api"')),
      );
    });

    test('rejects a missing required field', () {
      final data = clone();
      (data['blocks'] as Map<String, dynamic>)['login-01'] = block('login-01')
        ..remove('viewport');
      expect(
        validate(data).errors,
        contains(contains('blocks.login-01.viewport')),
      );
    });

    test('rejects an unknown viewport', () {
      final data = clone();
      (data['blocks'] as Map<String, dynamic>)['login-01'] = block('login-01')
        ..['viewport'] = 'tablet';
      expect(
        validate(data).errors,
        contains(contains('blocks.login-01.viewport')),
      );
    });

    test('rejects an id that is already a component', () {
      final data = clone();
      final blockAsComponent = block('login-01');
      blockAsComponent['entry'] = 'blocks/button/login.dart';
      blockAsComponent['files'] = ['blocks/button/login.dart'];
      (data['blocks'] as Map<String, dynamic>)['button'] = blockAsComponent;
      expect(
        validate(data).errors,
        contains(contains('blocks.button: the id is already a component')),
      );
    });

    test('rejects an entry outside blocks/<id>/', () {
      final data = clone();
      (data['blocks'] as Map<String, dynamic>)['login-01'] = block('login-01')
        ..['entry'] = 'components/login/login_01.dart';
      expect(
        validate(data).errors,
        contains(contains('blocks.login-01.entry')),
      );
    });

    test('rejects a non-Dart file entry', () {
      final data = clone();
      (data['blocks'] as Map<String, dynamic>)['login-01'] = block('login-01')
        ..['files'] = ['blocks/login-01/login_01.md'];
      expect(
        validate(data).errors,
        contains(contains('is not a Dart file')),
      );
    });

    test('rejects a docs entry outside blocks/<id>/', () {
      final data = clone();
      (data['blocks'] as Map<String, dynamic>)['login-01'] = block('login-01')
        ..['docs'] = ['components/login/README.md'];
      expect(
        validate(data).errors,
        contains(contains('blocks.login-01.docs')),
      );
    });
  });

  group('block deps', () {
    test('rejects a missing deps key', () {
      final data = clone();
      (data['blocks'] as Map<String, dynamic>)['login-01'] = block('login-01')
        ..['deps'] = {
          'foundation': <String>[],
          'theme': <String>[],
          'components': <String>[],
        };
      expect(
        validate(data).errors,
        contains(contains('blocks.login-01.deps: missing required key')),
      );
    });

    test('rejects a dep on another block', () {
      final data = clone();
      (data['blocks'] as Map<String, dynamic>)['login-01'] = block('login-01');
      final deps = Map<String, dynamic>.from(
        block('login-01')['deps'] as Map<String, dynamic>,
      );
      deps['components'] = ['dashboard-01'];
      (data['blocks'] as Map<String, dynamic>)['login-01']['deps'] = deps;
      expect(
        validate(data).errors,
        contains(contains('unknown component id "dashboard-01"')),
      );
    });

    test('rejects a dep on a missing component', () {
      final data = clone();
      final deps = Map<String, dynamic>.from(
        block('login-01')['deps'] as Map<String, dynamic>,
      );
      deps['components'] = ['ghost'];
      (data['blocks'] as Map<String, dynamic>)['login-01']['deps'] = deps;
      expect(
        validate(data).errors,
        contains(contains('unknown component id "ghost"')),
      );
    });

    test('rejects an unknown primitive dep', () {
      final data = clone();
      final deps = Map<String, dynamic>.from(
        block('login-01')['deps'] as Map<String, dynamic>,
      );
      deps['primitives'] = ['ghost'];
      (data['blocks'] as Map<String, dynamic>)['login-01']['deps'] = deps;
      expect(
        validate(data).errors,
        contains(contains('unknown primitive id "ghost"')),
      );
    });
  });

  group('fileHashes', () {
    test('requires a hash for every block file', () {
      final data = clone();
      (data['fileHashes'] as Map<String, dynamic>)
          .remove('blocks/login-01/login_01.dart');
      expect(
        validate(data).errors,
        contains(contains('missing entry for "blocks/login-01/login_01.dart"')),
      );
    });

    test('accepts markdown keys for block docs', () {
      final data = clone();
      (data['fileHashes']
              as Map<String, dynamic>)['blocks/login-01/README.md'] =
          List.filled(64, 'a').join();
      expect(validate(data).isValid, isTrue);
    });
  });
}
