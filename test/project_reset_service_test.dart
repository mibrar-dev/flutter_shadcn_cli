import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/reset/project_reset_service.dart';
import 'package:flutter_shadcn_cli/src/application/services/reset/reset_snapshot_manifest.dart';
import 'package:flutter_shadcn_cli/src/application/services/reset/reset_snapshot_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ResetSnapshotStore', () {
    late Directory tempHome;
    late Directory projectRoot;
    final now = DateTime.utc(2026, 5, 3, 12, 0, 0);

    setUp(() {
      tempHome = Directory.systemTemp.createTempSync('reset_store_home_');
      projectRoot = Directory.systemTemp.createTempSync('reset_store_project_');
      Directory(p.join(projectRoot.path, '.shadcn'))
          .createSync(recursive: true);
    });

    tearDown(() {
      if (tempHome.existsSync()) {
        tempHome.deleteSync(recursive: true);
      }
      if (projectRoot.existsSync()) {
        projectRoot.deleteSync(recursive: true);
      }
    });

    test('creates snapshot bundle under project-resets hash with manifest',
        () async {
      final configFile =
          File(p.join(projectRoot.path, '.shadcn', 'config.json'))
            ..writeAsStringSync('{"defaultNamespace":"shadcn"}');
      final componentFile = File(
        p.join(projectRoot.path, 'lib', 'ui', 'shadcn', 'components',
            'button.dart'),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync('class Button {}');

      final store = ResetSnapshotStore(
        homeDirectory: tempHome.path,
        clock: () => now,
        retention: const Duration(hours: 4),
      );

      final manifest = await store.createSnapshot(
        projectRoot: projectRoot.path,
        relativePaths: [
          '.shadcn/config.json',
          'lib/ui/shadcn/components/button.dart',
        ],
        deletedDirectoryRoots: [
          '.shadcn',
          'lib/ui/shadcn',
        ],
      );

      final bucket = Directory(
        p.join(
          tempHome.path,
          '.flutter_shadcn',
          'project-resets',
          store.projectKey(projectRoot.path),
        ),
      );
      expect(bucket.existsSync(), isTrue);
      final snapshots = bucket.listSync().whereType<Directory>().toList();
      expect(snapshots, hasLength(1));
      final snapshotDir = snapshots.single;
      expect(
          File(p.join(snapshotDir.path, 'manifest.json')).existsSync(), isTrue);
      expect(
        File(p.join(snapshotDir.path, 'files', '.shadcn', 'config.json'))
            .readAsStringSync(),
        configFile.readAsStringSync(),
      );
      expect(
        File(
          p.join(
            snapshotDir.path,
            'files',
            'lib',
            'ui',
            'shadcn',
            'components',
            'button.dart',
          ),
        ).readAsStringSync(),
        componentFile.readAsStringSync(),
      );
      expect(manifest.createdAtUtc, now);
      expect(manifest.expiresAtUtc, now.add(const Duration(hours: 4)));
      expect(
        manifest.relativePaths,
        containsAll([
          '.shadcn/config.json',
          'lib/ui/shadcn/components/button.dart',
        ]),
      );
      expect(manifest.deletedDirectoryRoots, ['.shadcn', 'lib/ui/shadcn']);
    });

    test('defaults snapshot retention to 24 hours', () async {
      File(p.join(projectRoot.path, '.shadcn', 'config.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');

      final store = ResetSnapshotStore(
        homeDirectory: tempHome.path,
        clock: () => now,
      );

      final manifest = await store.createSnapshot(
        projectRoot: projectRoot.path,
        relativePaths: ['.shadcn/config.json'],
        deletedDirectoryRoots: ['.shadcn'],
      );

      expect(manifest.expiresAtUtc, now.add(const Duration(hours: 24)));
    });

    test('restores latest non-expired snapshot for project', () async {
      File(p.join(projectRoot.path, '.shadcn', 'state.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{"managedDependencies":["gap"]}');
      File(p.join(
          projectRoot.path, 'lib', 'ui', 'shadcn', 'shared', 'theme.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('theme-v1');

      final store = ResetSnapshotStore(
        homeDirectory: tempHome.path,
        clock: () => now,
        retention: const Duration(hours: 1),
      );

      await store.createSnapshot(
        projectRoot: projectRoot.path,
        relativePaths: [
          '.shadcn/state.json',
          'lib/ui/shadcn/shared/theme.dart',
        ],
        deletedDirectoryRoots: ['.shadcn', 'lib/ui/shadcn/shared'],
      );

      Directory(p.join(projectRoot.path, '.shadcn'))
          .deleteSync(recursive: true);
      Directory(p.join(projectRoot.path, 'lib', 'ui', 'shadcn'))
          .deleteSync(recursive: true);

      final restored =
          await store.restoreLatestSnapshot(projectRoot: projectRoot.path);

      expect(restored, isNotNull);
      expect(
        File(p.join(projectRoot.path, '.shadcn', 'state.json'))
            .readAsStringSync(),
        '{"managedDependencies":["gap"]}',
      );
      expect(
        File(p.join(projectRoot.path, 'lib', 'ui', 'shadcn', 'shared',
                'theme.dart'))
            .readAsStringSync(),
        'theme-v1',
      );
    });

    test('refuses restore after snapshot expiry', () async {
      final key = ResetSnapshotStore(
        homeDirectory: tempHome.path,
        clock: () => now,
      ).projectKey(projectRoot.path);
      final bucket = Directory(
        p.join(
            tempHome.path, '.flutter_shadcn', 'project-resets', key, 'expired'),
      )..createSync(recursive: true);
      File(p.join(bucket.path, 'manifest.json')).writeAsStringSync(
        jsonEncode(
          ResetSnapshotManifest(
            projectPath: projectRoot.path,
            createdAtUtc: now.subtract(const Duration(hours: 3)),
            expiresAtUtc: now.subtract(const Duration(hours: 1)),
            relativePaths: const ['.shadcn/config.json'],
            deletedDirectoryRoots: const ['.shadcn'],
          ).toJson(),
        ),
      );

      final store = ResetSnapshotStore(
        homeDirectory: tempHome.path,
        clock: () => now,
      );

      await expectLater(
        () => store.restoreLatestSnapshot(projectRoot: projectRoot.path),
        throwsA(isA<ResetSnapshotExpiredException>()),
      );
    });

    test('prunes expired snapshots and leaves active ones', () async {
      final store = ResetSnapshotStore(
        homeDirectory: tempHome.path,
        clock: () => now,
      );
      final key = store.projectKey(projectRoot.path);
      final root = Directory(
        p.join(tempHome.path, '.flutter_shadcn', 'project-resets', key),
      )..createSync(recursive: true);

      final expiredDir = Directory(p.join(root.path, 'expired'))
        ..createSync(recursive: true);
      File(p.join(expiredDir.path, 'manifest.json')).writeAsStringSync(
        jsonEncode(
          ResetSnapshotManifest(
            projectPath: projectRoot.path,
            createdAtUtc: now.subtract(const Duration(days: 2)),
            expiresAtUtc: now.subtract(const Duration(hours: 1)),
            relativePaths: const [],
            deletedDirectoryRoots: const [],
          ).toJson(),
        ),
      );

      final activeDir = Directory(p.join(root.path, 'active'))
        ..createSync(recursive: true);
      File(p.join(activeDir.path, 'manifest.json')).writeAsStringSync(
        jsonEncode(
          ResetSnapshotManifest(
            projectPath: projectRoot.path,
            createdAtUtc: now,
            expiresAtUtc: now.add(const Duration(hours: 1)),
            relativePaths: const [],
            deletedDirectoryRoots: const [],
          ).toJson(),
        ),
      );

      final pruned = await store.pruneExpiredSnapshots();

      expect(pruned, 1);
      expect(expiredDir.existsSync(), isFalse);
      expect(activeDir.existsSync(), isTrue);
    });
  });

  group('ProjectResetService', () {
    late Directory tempHome;
    late Directory projectRoot;
    final now = DateTime.utc(2026, 5, 3, 12, 0, 0);

    setUp(() async {
      tempHome = Directory.systemTemp.createTempSync('project_reset_home_');
      projectRoot =
          Directory.systemTemp.createTempSync('project_reset_project_');

      await File(p.join(projectRoot.path, 'pubspec.yaml'))
          .create(recursive: true);
      await File(p.join(projectRoot.path, '.shadcn', 'config.json'))
          .create(recursive: true);
      await File(p.join(projectRoot.path, '.shadcn', 'config.json'))
          .writeAsString(
        '{"installPath":"lib/ui/shadcn","sharedPath":"lib/ui/shadcn/shared"}',
      );
      await File(p.join(projectRoot.path, '.shadcn', 'state.json'))
          .create(recursive: true);
      await File(p.join(projectRoot.path, '.shadcn', 'state.json'))
          .writeAsString(
        '{"managedDependencies":["gap"],"installPath":"lib/ui/shadcn","sharedPath":"lib/ui/shadcn/shared"}',
      );
      await File(p.join(projectRoot.path, '.shadcn', 'inline_actions.json'))
          .create(recursive: true);
      await File(p.join(projectRoot.path, '.shadcn', 'inline_actions.json'))
          .writeAsString('{"schemaVersion":1,"registries":{}}');
      File(
        p.join(projectRoot.path, 'lib', 'ui', 'shadcn', 'components',
            'button.dart'),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync('class Button {}');
      File(
        p.join(projectRoot.path, 'lib', 'ui', 'shadcn', 'shared', 'theme.dart'),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync('theme');
    });

    tearDown(() {
      if (tempHome.existsSync()) {
        tempHome.deleteSync(recursive: true);
      }
      if (projectRoot.existsSync()) {
        projectRoot.deleteSync(recursive: true);
      }
    });

    test('reset snapshots and deletes CLI-owned project artifacts', () async {
      final service = ProjectResetService(
        projectRoot: projectRoot.path,
        snapshotStore: ResetSnapshotStore(
          homeDirectory: tempHome.path,
          clock: () => now,
          retention: const Duration(minutes: 45),
        ),
      );

      final result = await service.reset();

      expect(
          Directory(p.join(projectRoot.path, '.shadcn')).existsSync(), isFalse);
      expect(
        Directory(p.join(projectRoot.path, 'lib', 'ui', 'shadcn')).existsSync(),
        isFalse,
      );
      expect(result.snapshot.createdAtUtc, now);
      expect(
          result.snapshot.expiresAtUtc, now.add(const Duration(minutes: 45)));
      expect(result.deletedDirectoryRoots, contains('.shadcn'));
      expect(result.deletedDirectoryRoots, contains('lib/ui/shadcn'));
    });

    test('undo restores the latest reset snapshot', () async {
      final store = ResetSnapshotStore(
        homeDirectory: tempHome.path,
        clock: () => now,
        retention: const Duration(minutes: 45),
      );
      final service = ProjectResetService(
        projectRoot: projectRoot.path,
        snapshotStore: store,
      );

      await service.reset();

      final restored = await service.undo();

      expect(restored.snapshot.projectPath, projectRoot.path);
      expect(
        File(p.join(projectRoot.path, '.shadcn', 'state.json'))
            .readAsStringSync(),
        contains('"managedDependencies":["gap"]'),
      );
      expect(
        File(p.join(projectRoot.path, 'lib', 'ui', 'shadcn', 'shared',
                'theme.dart'))
            .readAsStringSync(),
        'theme',
      );
    });
  });
}
