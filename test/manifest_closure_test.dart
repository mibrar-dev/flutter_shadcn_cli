import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/manifest_closure.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:test/test.dart';

void main() {
  late Map<String, dynamic> fixture;
  late RegistryManifest manifest;

  setUpAll(() {
    fixture = jsonDecode(
      File('test/fixtures/registry_v2/registry.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    manifest = RegistryManifest.fromJson(fixture);
  });

  ManifestClosure resolve(
    List<String> ids, {
    bool includeCore = true,
  }) {
    return ManifestClosureResolver(manifest).resolve(
      ids,
      includeCore: includeCore,
    );
  }

  group('closure', () {
    test('button pulls its layer units and files', () {
      final closure = resolve(['button']);
      expect(closure.components, ['button']);
      expect(closure.foundation, ['data', 'gap']);
      expect(closure.theme, ['color_tokens', 'theme']);
      expect(closure.primitives, ['clickable']);
      expect(
        closure.files,
        [
          'components/button/button.dart',
          'components/button/button_style.dart',
          'foundation/data.dart',
          'foundation/gap.dart',
          'primitives/clickable.dart',
          'theme/color_tokens.dart',
          'theme/color_utils.dart',
          'theme/theme.dart',
        ],
      );
    });

    test('component -> component and primitive -> primitive edges resolve', () {
      final closure = resolve(['text_area']);
      expect(closure.components, ['input', 'text_area']);
      expect(closure.primitives, ['clickable', 'form_core']);
      expect(
        closure.files,
        contains('components/input/input.dart'),
      );
      expect(
        closure.files,
        contains('components/text_area/text_area.dart'),
      );
    });

    test('includeCore false only keeps referenced foundation/theme units', () {
      final closure = resolve(['input'], includeCore: false);
      expect(closure.foundation, ['data']);
      // input declares both theme units, so both survive without the core.
      expect(closure.theme, ['color_tokens', 'theme']);
      expect(closure.files, isNot(contains('foundation/gap.dart')));
    });

    test('empty request with core returns every foundation and theme unit', () {
      final closure = resolve([]);
      expect(closure.components, isEmpty);
      expect(closure.primitives, isEmpty);
      expect(closure.foundation, ['data', 'gap']);
      expect(closure.theme, ['color_tokens', 'theme']);
    });

    test('collects the packages declared by the closure', () {
      final closure = resolve(['button']);
      expect(closure.packages.map((p) => p.name), ['intl']);
      expect(closure.packages.single.constraint, '^0.20.2');
    });

    test('is deterministic regardless of request order', () {
      final a = resolve(['text_area', 'button']);
      final b = resolve(['button', 'text_area']);
      expect(a.components, b.components);
      expect(a.files, b.files);
      expect(a.primitives, b.primitives);
    });
  });

  group('blocks', () {
    test('a block pulls its components, layers and its own file', () {
      final closure = ManifestClosureResolver(manifest).resolve(
        const [],
        blockIds: const ['login-01'],
      );
      expect(closure.blocks, ['login-01']);
      expect(closure.components, ['button', 'input']);
      expect(closure.files, contains('blocks/login-01/login_01.dart'));
      expect(
        closure.files,
        containsAll([
          'components/button/button.dart',
          'components/input/input.dart',
          'foundation/gap.dart',
        ]),
      );
    });

    test('a mixed request resolves component and block ids together', () {
      final closure = ManifestClosureResolver(manifest).resolve(
        const ['button', 'dashboard-01'],
      );
      expect(closure.blocks, ['dashboard-01']);
      expect(closure.components, containsAll(['button', 'input', 'text_area']));
      expect(
        closure.files,
        containsAll([
          'blocks/dashboard-01/dashboard_01.dart',
          'blocks/dashboard-01/dashboard_01_table.dart',
        ]),
      );
      // The block README is documentation: it never enters the closure.
      expect(
        closure.files,
        isNot(contains('blocks/dashboard-01/README.md')),
      );
    });

    test('the block package union is unchanged', () {
      final closure = ManifestClosureResolver(manifest).resolve(
        const ['login-01'],
      );
      expect(closure.packages.map((p) => p.name), ['intl']);
    });

    test('is deterministic regardless of request order', () {
      final a = ManifestClosureResolver(manifest).resolve(
        const ['button', 'dashboard-01'],
      );
      final b = ManifestClosureResolver(manifest).resolve(
        const ['dashboard-01', 'button'],
      );
      expect(a.blocks, b.blocks);
      expect(a.components, b.components);
      expect(a.files, b.files);
    });
  });

  group('errors', () {
    test('unknown component id throws with a clear message', () {
      expect(
        () => resolve(['nope']),
        throwsA(
          isA<ManifestClosureException>()
              .having((e) => e.kind, 'kind', 'component or block')
              .having((e) => e.id, 'id', 'nope')
              .having(
                (e) => e.toString(),
                'message',
                contains('Unknown component or block id "nope"'),
              ),
        ),
      );
    });

    test('unknown primitive referenced by a component throws', () {
      final broken = jsonDecode(jsonEncode(fixture)) as Map<String, dynamic>;
      final components = broken['components'] as Map<String, dynamic>;
      final button = Map<String, dynamic>.from(
        components['button'] as Map<String, dynamic>,
      );
      final deps = Map<String, dynamic>.from(
        button['deps'] as Map<String, dynamic>,
      );
      deps['primitives'] = ['ghost'];
      button['deps'] = deps;
      components['button'] = button;

      final brokenManifest = RegistryManifest.fromJson(broken);
      expect(
        () => ManifestClosureResolver(brokenManifest).resolve(['button']),
        throwsA(
          isA<ManifestClosureException>()
              .having((e) => e.kind, 'kind', 'primitive')
              .having((e) => e.id, 'id', 'ghost')
              .having((e) => e.referencedBy, 'referencedBy', 'button'),
        ),
      );
    });
  });

  group('cycle tolerance', () {
    test('a primitive cycle terminates and keeps both units', () {
      final cyclic = jsonDecode(jsonEncode(fixture)) as Map<String, dynamic>;
      final primitives = cyclic['primitives'] as Map<String, dynamic>;
      primitives['alpha'] = {
        'files': ['primitives/alpha.dart'],
        'deps': {
          'primitives': ['beta'],
        },
      };
      primitives['beta'] = {
        'files': ['primitives/beta.dart'],
        'deps': {
          'primitives': ['alpha'],
        },
      };
      final components = cyclic['components'] as Map<String, dynamic>;
      components['cyc'] = {
        'name': 'Cyc',
        'category': 'test',
        'description': 'cycle fixture',
        'entry': 'components/cyc/cyc.dart',
        'files': ['components/cyc/cyc.dart'],
        'userOwned': <String>[],
        'deps': {
          'foundation': <String>[],
          'theme': <String>[],
          'primitives': ['alpha'],
          'components': <String>[],
        },
        'tags': <String>[],
        'api': {
          'classes': ['Cyc'],
        },
      };

      final closure = ManifestClosureResolver(
        RegistryManifest.fromJson(cyclic),
      ).resolve(['cyc'], includeCore: false);
      expect(closure.primitives, ['alpha', 'beta']);
      expect(
        closure.files,
        containsAll(['primitives/alpha.dart', 'primitives/beta.dart']),
      );
    });
  });
}
