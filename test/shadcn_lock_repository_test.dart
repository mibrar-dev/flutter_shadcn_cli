import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String sha(String content) => FileHashing.ofText(content);

void main() {
  group('ShadcnLockRepository', () {
    late Directory tempRoot;
    late ShadcnLockRepository repository;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('shadcn_lock_v2_');
      repository = ShadcnLockRepository(tempRoot.path);
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    File writeProjectFile(String relativePath, String content) {
      final file = File(p.join(tempRoot.path, relativePath))
        ..createSync(recursive: true);
      return file..writeAsStringSync(content);
    }

    ShadcnLock installedLock() {
      return ShadcnLock(
        registry: ShadcnLockRegistry(
          name: 'shadcn_flutter',
          ref: 'refactor/rearchitecture',
          manifestSha256: sha('manifest-v1'),
        ),
        installRoot: 'lib/ui/shadcn',
        theme: LockThemeSelection(
          id: 'vercel',
          path: 'lib/ui/shadcn/theme/app_theme.dart',
          sha256: sha('app_theme'),
        ),
        layers: {
          LockLayer.foundation: LockLayerState(
            units: ['data'],
            files: {
              'lib/ui/shadcn/foundation/data.dart': sha('data.dart'),
            },
          ),
        },
        components: [
          ShadcnLockComponent(
            id: 'button',
            files: {
              'lib/ui/shadcn/components/button/button.dart': sha('button.dart'),
            },
            userOwned: {
              'lib/ui/shadcn/components/button/button_theme.dart':
                  sha('button_theme.dart'),
            },
          ),
        ],
      );
    }

    void installProjectFiles() {
      writeProjectFile('lib/ui/shadcn/foundation/data.dart', 'data.dart');
      writeProjectFile(
        'lib/ui/shadcn/components/button/button.dart',
        'button.dart',
      );
      writeProjectFile(
        'lib/ui/shadcn/components/button/button_theme.dart',
        'button_theme.dart',
      );
      writeProjectFile('lib/ui/shadcn/theme/app_theme.dart', 'app_theme');
    }

    test('a missing lock loads as an empty v2 lock', () async {
      expect(repository.existsSync(), isFalse);
      expect(await repository.exists(), isFalse);
      expect(await repository.loadIfPresent(), isNull);

      final lock = await repository.load();

      expect(lock.lockfileVersion, kLockfileVersion);
      expect(lock.components, isEmpty);
      expect(lock.layers, isEmpty);
    });

    test('save then load round-trips through disk', () async {
      installProjectFiles();
      final lock = installedLock();

      await repository.save(lock);
      final reloaded = await repository.load();

      expect(repository.existsSync(), isTrue);
      expect(jsonEncode(reloaded.toJson()), jsonEncode(lock.toJson()));
      final text = repository.file.readAsStringSync();
      expect(text.endsWith('\n'), isTrue);
      expect(text, contains('\n  "lockfileVersion": 2'));
      expect(jsonDecode(text), isA<Map<String, dynamic>>());
    });

    test('save creates the project root when it is missing', () async {
      final nested = ShadcnLockRepository(
        p.join(tempRoot.path, 'missing', 'app'),
      );

      await nested.save(const ShadcnLock());

      expect(nested.file.existsSync(), isTrue);
    });

    test('delete removes the lock and is safe to repeat', () async {
      await repository.save(const ShadcnLock());

      await repository.delete();
      await repository.delete();

      expect(repository.file.existsSync(), isFalse);
    });

    test('update performs a read-modify-write', () async {
      await repository.save(
        ShadcnLock(components: [ShadcnLockComponent(id: 'button')]),
      );

      final next = await repository.update(
        (current) => current
            .upsertComponent(ShadcnLockComponent(id: 'alert'))
            .copyWith(installRoot: 'lib/ui/shadcn'),
      );

      expect(next.componentIds, ['alert', 'button']);
      final reloaded = await repository.load();
      expect(reloaded.componentIds, ['alert', 'button']);
      expect(reloaded.installRoot, 'lib/ui/shadcn');
    });

    test('merge folds an incoming lock into the stored one', () async {
      await repository.save(
        ShadcnLock(
          registry: const ShadcnLockRegistry(name: 'shadcn_flutter'),
          components: [ShadcnLockComponent(id: 'button')],
        ),
      );

      await repository.merge(
        ShadcnLock(
          installRoot: 'lib/ui/shadcn',
          components: [ShadcnLockComponent(id: 'alert')],
        ),
      );

      final reloaded = await repository.load();
      expect(reloaded.componentIds, ['alert', 'button']);
      expect(reloaded.installRoot, 'lib/ui/shadcn');
      expect(reloaded.registry.name, 'shadcn_flutter');
    });

    group('corrupt input', () {
      void writeLock(String content) =>
          repository.file.writeAsStringSync(content);

      test('empty file', () async {
        writeLock('   \n');

        expect(
          repository.load,
          throwsA(
            isA<LockFileException>().having(
              (error) => error.message,
              'message',
              contains('empty'),
            ),
          ),
        );
      });

      test('not JSON', () async {
        writeLock('{ not json');

        expect(
          repository.load,
          throwsA(
            isA<LockFileException>().having(
              (error) => error.message,
              'message',
              contains('not valid JSON'),
            ),
          ),
        );
      });

      test('JSON array instead of an object', () async {
        writeLock('[]');

        expect(
          repository.load,
          throwsA(
            isA<LockFileException>().having(
              (error) => error.message,
              'message',
              contains('JSON object'),
            ),
          ),
        );
      });

      test('v1 lock is refused with migration guidance', () async {
        writeLock(
          jsonEncode({
            'lockfileVersion': 1,
            'registries': {'shadcn': <String, dynamic>{}},
            'components': <dynamic>[],
          }),
        );

        await expectLater(
          repository.load,
          throwsA(
            isA<LockFileException>().having(
              (error) => error.message,
              'message',
              allOf(contains('1'), contains('no longer supported')),
            ),
          ),
        );
        expect(
          () => repository.parse(jsonEncode({'lockfileVersion': 1})),
          throwsA(isA<LockFileException>()),
        );
      });

      test('a component that is not an object is skipped, not fatal', () async {
        writeLock(
          jsonEncode({
            'lockfileVersion': 2,
            'components': [
              'button',
              {'id': 'alert'}
            ],
          }),
        );

        final lock = await repository.load();

        expect(lock.componentIds, ['alert']);
      });
    });

    group('inspect', () {
      test('reports a clean install', () async {
        installProjectFiles();
        final lock = installedLock();

        final report = await repository.inspect(lock);

        expect(report.isClean, isTrue);
        expect(report.files, hasLength(4));
        expect(report.unchanged, hasLength(4));
        expect(report.modified, isEmpty);
        expect(report.missing, isEmpty);
        expect(report.registryMoved, isFalse);
      });

      test('detects a locally modified registry-owned file', () async {
        installProjectFiles();
        writeProjectFile(
          'lib/ui/shadcn/components/button/button.dart',
          'button.dart // edited',
        );

        final report = await repository.inspect(installedLock());

        expect(report.modified.map((file) => file.path), [
          'lib/ui/shadcn/components/button/button.dart',
        ]);
        expect(report.modified.single.owner, 'button');
        expect(report.modified.single.actualSha, sha('button.dart // edited'));
        expect(report.isClean, isFalse);
        expect(
            report.updatablePaths,
            isNot(contains(
              'lib/ui/shadcn/components/button/button.dart',
            )));
        expect(report.updatablePaths,
            contains('lib/ui/shadcn/foundation/data.dart'));
      });

      test('detects a deleted file', () async {
        installProjectFiles();
        File(
          p.join(tempRoot.path, 'lib/ui/shadcn/foundation/data.dart'),
        ).deleteSync();

        final report = await repository.inspect(installedLock());

        expect(report.missing.map((file) => file.path), [
          'lib/ui/shadcn/foundation/data.dart',
        ]);
        expect(report.missing.single.owner, 'foundation');
        expect(report.missing.single.actualSha, isNull);
      });

      test('reports user-owned drift but never marks it updatable', () async {
        installProjectFiles();
        const themeFile = 'lib/ui/shadcn/components/button/button_theme.dart';
        writeProjectFile(themeFile, 'button_theme.dart // mine');

        final report = await repository.inspect(installedLock());

        expect(report.userOwnedDrift.map((file) => file.path), [themeFile]);
        expect(report.userOwnedDrift.single.isModified, isTrue);
        expect(report.hasUserOwnedDrift, isTrue);
        expect(report.updatablePaths, isNot(contains(themeFile)));
        expect(report.registryOwnedDrift.map((file) => file.path), isEmpty);
      });

      test('flags a missing user-owned file without failing the check',
          () async {
        installProjectFiles();
        const themeFile = 'lib/ui/shadcn/components/button/button_theme.dart';
        File(p.join(tempRoot.path, themeFile)).deleteSync();

        final report = await repository.inspect(installedLock());

        expect(report.missing.map((file) => file.path), contains(themeFile));
        expect(report.isClean, isTrue);
      });

      test('a user-owned entry always wins over a registry-owned one',
          () async {
        installProjectFiles();
        const themeFile = 'lib/ui/shadcn/components/button/button_theme.dart';
        final lock = installedLock().upsertComponent(
          ShadcnLockComponent(
            id: 'menu',
            files: {themeFile: sha('menu theme')},
          ),
        );

        final report = await repository.inspect(lock);

        expect(
            report.files
                .where((file) => file.path == themeFile)
                .single
                .userOwned,
            isTrue);
        expect(report.updatablePaths, isNot(contains(themeFile)));
      });

      test('narrows the scan to the requested components', () async {
        installProjectFiles();
        writeProjectFile('lib/ui/shadcn/components/alert/alert.dart', 'alert');
        const themeFile = 'lib/ui/shadcn/components/button/button_theme.dart';
        final lock = installedLock().upsertComponent(
          ShadcnLockComponent(
            id: 'alert',
            files: {'lib/ui/shadcn/components/alert/alert.dart': sha('alert')},
          ),
        );

        final report = await repository.inspect(lock, componentIds: {'button'});

        expect(
            report.files.map((file) => file.owner), isNot(contains('alert')));
        expect(report.files.map((file) => file.path), contains(themeFile));
      });

      test('flags a moved registry manifest', () async {
        installProjectFiles();
        final lock = installedLock();

        expect((await repository.inspect(lock)).registryMoved, isFalse);

        final moved = await repository.inspect(
          lock,
          manifestSha256: sha('manifest-v2'),
        );
        expect(moved.registryMoved, isTrue);
        expect(moved.currentManifestSha256, sha('manifest-v2'));
        expect(moved.isClean, isFalse);

        expect(
          (await repository.inspect(lock, manifestSha256: sha('manifest-v1')))
              .registryMoved,
          isFalse,
        );
      });

      test('inspectInstalled reads the lock from disk', () async {
        installProjectFiles();
        await repository.save(installedLock());

        final report = await repository.inspectInstalled();

        expect(report.isClean, isTrue);
        expect(report.files, hasLength(4));
      });

      test('serialises for --json output', () async {
        installProjectFiles();
        final report = await repository.inspect(installedLock());

        final json = report.toJson();
        expect(json['clean'], isTrue);
        expect((json['counts']! as Map)['total'], 4);
        expect((json['files']! as List), hasLength(4));
      });
    });

    test('hashInstalled hashes the files that exist', () async {
      installProjectFiles();

      final digests = await repository.hashInstalled([
        'lib/ui/shadcn/foundation/data.dart',
        'lib/ui/shadcn/nope.dart',
      ]);

      expect(digests, {
        'lib/ui/shadcn/foundation/data.dart': sha('data.dart'),
      });
    });

    test('resolve joins relative paths onto the project root', () {
      expect(
        repository.resolve('lib/ui/shadcn/button.dart').path,
        p.join(tempRoot.path, 'lib/ui/shadcn/button.dart'),
      );
    });
  });
}
