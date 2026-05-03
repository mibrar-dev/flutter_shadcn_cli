import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_shadcn_cli/src/application/services/reset/reset_snapshot_manifest.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/resolver/v1/project_path_guard.dart';
import 'package:path/path.dart' as p;

class ResetSnapshotExpiredException implements Exception {
  final String projectRoot;

  const ResetSnapshotExpiredException(this.projectRoot);

  @override
  String toString() => 'Reset snapshot for $projectRoot has expired.';
}

class ResetSnapshotStore {
  final String homeDirectory;
  final DateTime Function() clock;
  final Duration retention;

  ResetSnapshotStore({
    required this.homeDirectory,
    DateTime Function()? clock,
    Duration? retention,
  })  : clock = clock ?? (() => DateTime.now().toUtc()),
        retention = retention ?? const Duration(hours: 24);

  String projectKey(String projectRoot) {
    final normalized = p.normalize(p.absolute(projectRoot));
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  Future<ResetSnapshotManifest> createSnapshot({
    required String projectRoot,
    required List<String> relativePaths,
    required List<String> deletedDirectoryRoots,
  }) async {
    final createdAtUtc = clock().toUtc();
    final expiresAtUtc = createdAtUtc.add(retention);
    final normalizedProjectRoot = p.normalize(p.absolute(projectRoot));
    final snapshotDir = Directory(
      p.join(
        _projectSnapshotsRoot(projectRoot).path,
        '${createdAtUtc.microsecondsSinceEpoch}',
      ),
    );
    await snapshotDir.create(recursive: true);

    final sanitizedPaths =
        relativePaths.map(_sanitizeRelativePath).toSet().toList()..sort();
    for (final relativePath in sanitizedPaths) {
      final source = File(
        ProjectPathGuard.resolveSafeWritePath(
          projectRoot: normalizedProjectRoot,
          destinationRelativePath: relativePath,
        ),
      );
      if (!await source.exists()) {
        continue;
      }

      final destination =
          File(_snapshotFilePath(snapshotDir.path, relativePath));
      if (!await destination.parent.exists()) {
        await destination.parent.create(recursive: true);
      }
      await destination.writeAsBytes(await source.readAsBytes(), flush: true);
    }

    final manifest = ResetSnapshotManifest(
      projectPath: normalizedProjectRoot,
      createdAtUtc: createdAtUtc,
      expiresAtUtc: expiresAtUtc,
      relativePaths: sanitizedPaths,
      deletedDirectoryRoots:
          deletedDirectoryRoots.map(_sanitizeRelativePath).toList(),
    );
    await File(p.join(snapshotDir.path, 'manifest.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      flush: true,
    );
    return manifest;
  }

  Future<ResetSnapshotManifest?> restoreLatestSnapshot({
    required String projectRoot,
  }) async {
    final snapshotDir = await _latestSnapshotDirectory(projectRoot);
    if (snapshotDir == null) {
      return null;
    }

    final manifest = await _loadManifest(snapshotDir);
    if (manifest.expiresAtUtc.isBefore(clock().toUtc())) {
      throw ResetSnapshotExpiredException(projectRoot);
    }

    for (final relativePath in manifest.relativePaths) {
      final source = File(_snapshotFilePath(snapshotDir.path, relativePath));
      if (!await source.exists()) {
        continue;
      }
      final destination = File(
        ProjectPathGuard.resolveSafeWritePath(
          projectRoot: projectRoot,
          destinationRelativePath: relativePath,
        ),
      );
      if (!await destination.parent.exists()) {
        await destination.parent.create(recursive: true);
      }
      await destination.writeAsBytes(await source.readAsBytes(), flush: true);
    }

    return manifest;
  }

  Future<int> pruneExpiredSnapshots() async {
    final root = _resetRoot();
    if (!await root.exists()) {
      return 0;
    }

    var pruned = 0;
    await for (final projectBucket in root.list()) {
      if (projectBucket is! Directory) {
        continue;
      }
      await for (final snapshot in projectBucket.list()) {
        if (snapshot is! Directory) {
          continue;
        }
        final manifestFile = File(p.join(snapshot.path, 'manifest.json'));
        if (!await manifestFile.exists()) {
          continue;
        }
        final manifest = await _loadManifest(snapshot);
        if (manifest.expiresAtUtc.isBefore(clock().toUtc())) {
          await snapshot.delete(recursive: true);
          pruned++;
        }
      }
    }
    return pruned;
  }

  Directory _resetRoot() {
    return Directory(
        p.join(homeDirectory, '.flutter_shadcn', 'project-resets'));
  }

  Directory _projectSnapshotsRoot(String projectRoot) {
    return Directory(p.join(_resetRoot().path, projectKey(projectRoot)));
  }

  String _snapshotFilePath(String snapshotDir, String relativePath) {
    final sanitized = _sanitizeRelativePath(relativePath);
    final destination = p.normalize(p.join(snapshotDir, 'files', sanitized));
    final expectedRoot = p.normalize(p.join(snapshotDir, 'files'));
    if (destination != expectedRoot && !p.isWithin(expectedRoot, destination)) {
      throw ArgumentError.value(
          relativePath, 'relativePath', 'Path escapes snapshot bundle');
    }
    return destination;
  }

  Future<Directory?> _latestSnapshotDirectory(String projectRoot) async {
    final projectBucket = _projectSnapshotsRoot(projectRoot);
    if (!await projectBucket.exists()) {
      return null;
    }

    final snapshots = await projectBucket
        .list()
        .where((entity) => entity is Directory)
        .cast<Directory>()
        .toList();
    if (snapshots.isEmpty) {
      return null;
    }

    snapshots.sort((left, right) =>
        p.basename(right.path).compareTo(p.basename(left.path)));
    return snapshots.first;
  }

  Future<ResetSnapshotManifest> _loadManifest(Directory snapshotDir) async {
    final manifestFile = File(p.join(snapshotDir.path, 'manifest.json'));
    final payload = jsonDecode(await manifestFile.readAsString());
    return ResetSnapshotManifest.fromJson(
      (payload as Map).map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  String _sanitizeRelativePath(String relativePath) {
    final trimmed = relativePath.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
          relativePath, 'relativePath', 'Path cannot be empty');
    }
    if (p.isAbsolute(trimmed)) {
      throw ArgumentError.value(
          relativePath, 'relativePath', 'Path must be project-relative');
    }
    final normalized = p.normalize(trimmed);
    if (normalized == '..' || normalized.startsWith('../')) {
      throw ArgumentError.value(
          relativePath, 'relativePath', 'Path escapes root');
    }
    return normalized;
  }
}
