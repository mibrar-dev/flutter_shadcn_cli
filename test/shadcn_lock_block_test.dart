import 'dart:convert';

import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:test/test.dart';

/// `shadcn.lock` v2 records the blocks layer (P6-B2): an id, its files with
/// their install-time hashes and its closure.
void main() {
  ShadcnLockBlock block({String id = 'login-01'}) => ShadcnLockBlock(
        id: id,
        files: {
          'lib/ui/shadcn/blocks/$id/${id.replaceAll('-', '_')}.dart': 'a' * 64
        },
        deps: const LockComponentDeps(components: ['button']),
      );

  group('ShadcnLockBlock', () {
    test('parses and re-serialises', () {
      final parsed = ShadcnLockBlock.fromJson({
        'id': 'login-01',
        'version': '1.0.0',
        'files': {'lib/ui/shadcn/blocks/login-01/login_01.dart': 'b' * 64},
        'deps': {
          'components': ['button', 'input'],
          'primitives': <String>[],
          'foundation': <String>[],
          'theme': <String>[],
        },
      });
      expect(parsed.paths, ['lib/ui/shadcn/blocks/login-01/login_01.dart']);
      expect(parsed.deps.components, ['button', 'input']);
      expect(parsed.toJson()['version'], '1.0.0');
    });

    test('rejects an empty id', () {
      expect(
        () => ShadcnLockBlock(id: '  '),
        throwsA(isA<LockFileException>()),
      );
    });

    test('rejects a non-digest hash', () {
      expect(
        () => ShadcnLockBlock(
          id: 'login-01',
          files: const {'blocks/login-01/login_01.dart': 'nope'},
        ),
        throwsA(isA<LockFileException>()),
      );
    });
  });

  group('ShadcnLock', () {
    test('records and forgets a block', () {
      final lock = const ShadcnLock().upsertBlock(block());
      expect(lock.blockIds, ['login-01']);
      expect(lock.blockFor('login-01')!.deps.components, ['button']);
      expect(
        lock.registryOwnedPaths,
        contains('lib/ui/shadcn/blocks/login-01/login_01.dart'),
      );
      expect(lock.ownerOf('lib/ui/shadcn/blocks/login-01/login_01.dart'),
          'login-01');
      expect(
          lock.dependentsOf({
            'lib/ui/shadcn/components/button/button.dart',
          }),
          isEmpty);
      expect(lock.removeBlock('login-01').blockIds, isEmpty);
    });

    test('a block is never a user-owned path', () {
      final lock = const ShadcnLock().upsertBlock(block());
      expect(lock.userOwnedPaths, isEmpty);
      expect(lock.updatablePaths,
          contains('lib/ui/shadcn/blocks/login-01/login_01.dart'));
    });

    test('keeps the block list sorted', () {
      final lock = const ShadcnLock()
          .upsertBlock(block(id: 'login-02'))
          .upsertBlock(block(id: 'login-01'));
      expect(lock.blockIds, ['login-01', 'login-02']);
    });

    test('merges blocks by id', () {
      final first = const ShadcnLock().upsertBlock(block());
      final second = const ShadcnLock().upsertBlock(block(id: 'login-02'));
      expect(first.mergeWith(second).blockIds, ['login-01', 'login-02']);
    });

    test('round-trips through JSON, including an absent blocks key', () {
      final lock = const ShadcnLock().mergeLayer(
        LockLayer.theme,
        units: const {'theme'},
        files: {'lib/ui/shadcn/theme/theme.dart': 'c' * 64},
      ).upsertBlock(block());
      final restored = ShadcnLock.fromJson(lock.toJson());
      expect(restored.blockIds, ['login-01']);
      expect(restored.blockFor('login-01')!.files.values.single, 'a' * 64);
      expect(restored.layerState(LockLayer.theme).units, ['theme']);

      // A lock written before the blocks layer existed still parses.
      final legacy = ShadcnLock.fromJson(const {
        'lockfileVersion': 2,
        'installRoot': 'lib/ui/shadcn',
      });
      expect(legacy.blocks, isEmpty);
      expect(legacy.isEmpty, isTrue);
    });

    test('rejects a blocks entry that is not an array', () {
      expect(
        () => ShadcnLock.fromJson(const {
          'lockfileVersion': 2,
          'blocks': {'login-01': {}},
        }),
        throwsA(isA<LockFileException>()),
      );
    });

    test('serialises blocks next to components', () {
      final lock = const ShadcnLock().upsertBlock(block());
      final text =
          '${const JsonEncoder.withIndent('  ').convert(lock.toJson())}\n';
      final json = ShadcnLockRepository('/unused').parse(text);
      expect(json.blockIds, ['login-01']);
      expect(
        text,
        contains('"blocks"'),
        reason: 'the block list is always written, like components',
      );
    });
  });
}
