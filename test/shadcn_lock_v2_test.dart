import 'dart:convert';

import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:test/test.dart';

String sha(String content) => FileHashing.ofText(content);

ShadcnLockComponent buttonComponent() {
  return ShadcnLockComponent(
    id: 'button',
    version: '1.0.0',
    files: {
      'lib/ui/shadcn/components/button/button.dart': sha('button.dart'),
      'lib/ui/shadcn/components/button/button_style.dart':
          sha('button_style.dart'),
    },
    userOwned: {
      'lib/ui/shadcn/components/button/button_theme.dart':
          sha('button_theme.dart'),
    },
    deps: const LockComponentDeps(
      foundation: ['data', 'gap'],
      theme: ['theme'],
      primitives: ['clickable'],
    ),
    api: const LockComponentApi(
      byKind: {
        'classes': ['Button', 'ButtonGroup'],
        'enums': ['ButtonVariant'],
      },
    ),
  );
}

ShadcnLock sampleLock() {
  return ShadcnLock(
    registry: ShadcnLockRegistry(
      name: 'shadcn_flutter',
      ref: 'refactor/rearchitecture',
      manifestSha256: sha('manifest.json'),
      generatedAt: '2026-10-09T00:00:00Z',
    ),
    installRoot: 'lib/ui/shadcn',
    theme: LockThemeSelection(
      id: 'vercel',
      path: 'lib/ui/shadcn/theme/app_theme.dart',
      sha256: sha('app_theme.dart'),
    ),
    layers: {
      LockLayer.foundation: LockLayerState(
        units: ['data', 'gap'],
        files: {'lib/ui/shadcn/foundation/data.dart': sha('data.dart')},
      ),
      LockLayer.theme: LockLayerState(
        units: ['theme'],
        files: {'lib/ui/shadcn/theme/theme.dart': sha('theme.dart')},
      ),
      LockLayer.primitives: LockLayerState(
        units: ['clickable'],
        files: {
          'lib/ui/shadcn/primitives/clickable.dart': sha('clickable.dart')
        },
      ),
    },
    components: [buttonComponent()],
  );
}

void main() {
  group('ShadcnLock round-trip', () {
    test('survives toJson -> fromJson unchanged', () {
      final lock = sampleLock();
      final encoded = jsonEncode(lock.toJson());
      final reparsed = ShadcnLock.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );

      expect(jsonEncode(reparsed.toJson()), encoded);
      expect(reparsed.lockfileVersion, kLockfileVersion);
      expect(reparsed.registry.name, 'shadcn_flutter');
      expect(reparsed.registry.ref, 'refactor/rearchitecture');
      expect(reparsed.registry.manifestSha256, sha('manifest.json'));
      expect(reparsed.installRoot, 'lib/ui/shadcn');
      expect(reparsed.theme!.id, 'vercel');
      expect(reparsed.layerState(LockLayer.foundation).units, ['data', 'gap']);
      expect(reparsed.componentIds, ['button']);
      expect(reparsed.componentFor('button')!.userOwnedPaths, [
        'lib/ui/shadcn/components/button/button_theme.dart',
      ]);
      expect(reparsed.componentFor('button')!.api.symbols, {
        'Button',
        'ButtonGroup',
        'ButtonVariant',
      });
    });

    test('serialises deterministically: sorted keys, sorted components', () {
      final lock = ShadcnLock(
        installRoot: 'lib/ui/shadcn',
        components: [
          ShadcnLockComponent(
              id: 'tabs', files: {'b.dart': sha('b'), 'a.dart': sha('a')}),
          ShadcnLockComponent(id: 'button', files: {'z.dart': sha('z')}),
        ],
      );

      final json = lock.toJson();
      final components = json['components']! as List;
      expect((components.first as Map)['id'], 'button');
      expect(
        ((components.last as Map)['files']! as Map).keys,
        ['a.dart', 'b.dart'],
      );
      expect(
          (json['layers']! as Map).keys, ['foundation', 'theme', 'primitives']);
    });

    test('tolerates a minimal document', () {
      final lock = ShadcnLock.fromJson(const {'lockfileVersion': 2});

      expect(lock.components, isEmpty);
      expect(lock.layers, isEmpty);
      expect(lock.theme, isNull);
      expect(lock.installRoot, '');
      expect(lock.isEmpty, isTrue);
      expect(lock.layerState(LockLayer.theme).isEmpty, isTrue);
    });

    test('rejects a v1 lock', () {
      expect(
        () => ShadcnLock.fromJson(const {
          'lockfileVersion': 1,
          'registries': <String, dynamic>{},
          'components': <dynamic>[],
        }),
        throwsA(
          isA<LockFileException>().having(
            (error) => error.message,
            'message',
            contains('no longer supported'),
          ),
        ),
      );
      expect(
        () => ShadcnLock.fromJson(const <String, dynamic>{}),
        throwsA(isA<LockFileException>()),
      );
    });

    test('rejects a non sha256 digest', () {
      expect(
        () => ShadcnLock.fromJson({
          'lockfileVersion': 2,
          'layers': {
            'foundation': {
              'files': {'lib/ui/shadcn/foundation/data.dart': 'not-a-digest'},
            },
          },
        }),
        throwsA(
          isA<LockFileException>().having(
            (error) => error.message,
            'message',
            contains('data.dart'),
          ),
        ),
      );
    });

    test('normalises windows separators and ./ prefixes in paths', () {
      final lock = ShadcnLock.fromJson({
        'lockfileVersion': 2,
        'components': [
          {
            'id': 'button',
            'files': {
              '.\\lib\\ui\\shadcn\\components\\button\\button.dart': sha('x')
            },
          },
        ],
      });

      expect(
        lock.componentFor('button')!.paths,
        ['lib/ui/shadcn/components/button/button.dart'],
      );
    });

    test('ignores unknown layer keys', () {
      final lock = ShadcnLock.fromJson({
        'lockfileVersion': 2,
        'layers': {
          'foundation': {
            'units': ['data'],
            'files': {'lib/ui/shadcn/foundation/data.dart': sha('x')},
          },
          'widgets': {
            'units': ['nope']
          },
        },
      });

      expect(lock.layers.keys, [LockLayer.foundation]);
    });
  });

  group('user-owned files', () {
    test('are never updatable and stay out of registryOwnedPaths', () {
      final lock = sampleLock();
      final themeFile = 'lib/ui/shadcn/components/button/button_theme.dart';

      expect(lock.isUserOwned(themeFile), isTrue);
      expect(lock.userOwnedPaths, {themeFile});
      expect(lock.registryOwnedPaths.contains(themeFile), isFalse);
      expect(lock.updatablePaths.contains(themeFile), isFalse);
      expect(lock.updatablePaths,
          contains('lib/ui/shadcn/components/button/button.dart'));
      expect(
        lock.componentFor('button')!.updatableFiles.keys,
        isNot(contains(themeFile)),
      );
      expect(lock.ownerOf(themeFile), 'button');
    });

    test('a path in both files and userOwned is a corrupt lock', () {
      const path = 'lib/ui/shadcn/components/button/button_theme.dart';
      expect(
        () => ShadcnLockComponent(
          id: 'button',
          files: {path: sha('x')},
          userOwned: {path: sha('x')},
        ),
        throwsA(
          isA<LockFileException>().having(
            (error) => error.message,
            'message',
            contains('never be registry-owned'),
          ),
        ),
      );
    });

    test('withUserOwnedFile moves a path out of the updatable set', () {
      const path = 'lib/ui/shadcn/components/button/button_theme.dart';
      final component =
          ShadcnLockComponent(id: 'button', files: {path: sha('x')});

      final owned = component.withUserOwnedFile(path, sha('x'));

      expect(owned.files, isEmpty);
      expect(owned.isUserOwned(path), isTrue);
      expect(owned.updatableFiles, isEmpty);
    });

    test('remove drops the component and exposes its user files for purge', () {
      final lock = sampleLock();

      final removed = lock.removeComponent('button');
      expect(removed.components, isEmpty);
      expect(
        removed.updatablePaths,
        isNot(contains('lib/ui/shadcn/components/button/button.dart')),
      );
      // `remove` leaves the user file on disk unless --purge-user-themes is
      // given; the dropped record is what tells it which files that is.
      expect(lock.componentFor('button')!.userOwnedPaths, [
        'lib/ui/shadcn/components/button/button_theme.dart',
      ]);
    });
  });

  group('merge', () {
    test('unions layer units and files, keeping the newest hashes', () {
      final current = ShadcnLock(
        layers: {
          LockLayer.foundation: LockLayerState(
            units: ['data'],
            files: {'lib/ui/shadcn/foundation/data.dart': sha('old')},
          ),
        },
      );
      final incoming = ShadcnLock(
        registry: const ShadcnLockRegistry(name: 'shadcn_flutter'),
        installRoot: 'lib/ui/shadcn',
        layers: {
          LockLayer.foundation: LockLayerState(
            units: ['gap'],
            files: {'lib/ui/shadcn/foundation/gap.dart': sha('gap')},
          ),
        },
      );

      final merged = current.mergeWith(incoming);

      expect(merged.layerState(LockLayer.foundation).units, ['data', 'gap']);
      expect(merged.layerState(LockLayer.foundation).files.keys, [
        'lib/ui/shadcn/foundation/data.dart',
        'lib/ui/shadcn/foundation/gap.dart',
      ]);
      expect(
        merged
            .layerState(LockLayer.foundation)
            .files['lib/ui/shadcn/foundation/data.dart'],
        sha('old'),
      );
      expect(merged.registry.name, 'shadcn_flutter');
      expect(merged.installRoot, 'lib/ui/shadcn');
    });

    test('upserts components by id and keeps the list sorted', () {
      final lock = ShadcnLock(components: [buttonComponent()])
          .upsertComponent(ShadcnLockComponent(id: 'alert'))
          .upsertComponent(
            ShadcnLockComponent(
              id: 'button',
              files: {
                'lib/ui/shadcn/components/button/button.dart': sha('new')
              },
            ),
          );

      expect(lock.componentIds, ['alert', 'button']);
      expect(
        lock.componentFor('button')!.files.values.single,
        sha('new'),
      );
    });

    test('mergeWith lets the incoming component replace an installed one', () {
      final installed = ShadcnLock(components: [buttonComponent()]);
      final incoming = ShadcnLock(
        components: [
          ShadcnLockComponent(
            id: 'button',
            files: {'lib/ui/shadcn/components/button/button.dart': sha('new')},
          ),
        ],
      );

      expect(installed.mergeWith(incoming).componentFor('button')!.paths, [
        'lib/ui/shadcn/components/button/button.dart',
      ]);
    });
  });

  group('api', () {
    test('reads symbol -> owner maps as declared symbols', () {
      final api = LockComponentApi.fromJson({
        'classes': ['Button'],
        'enums': ['ButtonVariant'],
        // meta.json maps such as providedBy are symbol -> owner.
        'providedBy': {'Button': 'button.dart'},
        'ignored': 42,
      });

      expect(api.symbolsFor('classes'), ['Button']);
      expect(api.symbols, {'Button', 'ButtonVariant'});
      expect(api.declares('Button'), isTrue);
      expect(api.declares('ButtonGroup'), isFalse);
      expect(api.toJson(), {
        'classes': ['Button'],
        'enums': ['ButtonVariant'],
        'providedBy': ['Button'],
      });
    });

    test('mergeWith unions symbols per kind', () {
      const left = LockComponentApi(
        byKind: {
          'classes': ['Button'],
        },
      );
      const right = LockComponentApi(
        byKind: {
          'classes': ['ButtonGroup'],
          'enums': ['ButtonSize'],
        },
      );

      final merged = left.mergeWith(right);

      expect(merged.symbolsFor('classes'), ['Button', 'ButtonGroup']);
      expect(merged.symbolsFor('enums'), ['ButtonSize']);
    });

    test('a component without api declares nothing', () {
      final component = ShadcnLockComponent(id: 'button');

      expect(component.api.symbols, isEmpty);
      expect(component.api.toJson(), isEmpty);
      expect(component.copyWith(api: buttonComponent().api).api.symbols, {
        'Button',
        'ButtonGroup',
        'ButtonVariant',
      });
    });
  });

  group('queries', () {
    test('ownerOf resolves component, layer and theme paths', () {
      final lock = sampleLock();

      expect(lock.ownerOf('lib/ui/shadcn/components/button/button.dart'),
          'button');
      expect(lock.ownerOf('lib/ui/shadcn/primitives/clickable.dart'),
          'primitives');
      expect(lock.ownerOf('lib/ui/shadcn/theme/app_theme.dart'), 'theme');
      expect(lock.ownerOf('lib/ui/shadcn/other.dart'), isNull);
    });

    test('dependentsOf counts user-owned files too', () {
      final lock = sampleLock();

      expect(
        lock.dependentsOf(
            {'lib/ui/shadcn/components/button/button_theme.dart'}),
        {'button'},
      );
      expect(lock.dependentsOf({'lib/ui/shadcn/nothing.dart'}), isEmpty);
    });

    test('registry.hasMoved compares manifest digests', () {
      final registry = ShadcnLockRegistry(manifestSha256: sha('a'));

      expect(registry.hasMoved(sha('a')), isFalse);
      expect(registry.hasMoved(sha('b')), isTrue);
      expect(registry.hasMoved(''), isFalse);
      expect(
        const ShadcnLockRegistry().hasMoved(sha('a')),
        isFalse,
      );
    });

    test('deps resolve per layer and merge as a union', () {
      const deps = LockComponentDeps(
        foundation: ['data'],
        primitives: ['clickable'],
      );

      expect(deps.forLayer(LockLayer.foundation), ['data']);
      expect(deps.references(LockLayer.primitives, 'clickable'), isTrue);
      expect(deps.references(LockLayer.theme, 'theme'), isFalse);
      expect(deps.layerUnits, {'data', 'clickable'});
      expect(
        deps
            .mergeWith(const LockComponentDeps(primitives: ['overlay']))
            .primitives,
        ['clickable', 'overlay'],
      );
    });
  });
}
