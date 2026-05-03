import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/reset/reset_snapshot_manifest.dart';
import 'package:flutter_shadcn_cli/src/application/services/reset/reset_snapshot_store.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/inline_action_journal.dart';
import 'package:flutter_shadcn_cli/src/state.dart';
import 'package:path/path.dart' as p;

class ProjectResetResult {
  final ResetSnapshotManifest snapshot;
  final List<String> deletedDirectoryRoots;

  const ProjectResetResult({
    required this.snapshot,
    required this.deletedDirectoryRoots,
  });
}

class ProjectResetUndoResult {
  final ResetSnapshotManifest snapshot;

  const ProjectResetUndoResult({required this.snapshot});
}

class ProjectResetService {
  final String projectRoot;
  final ResetSnapshotStore snapshotStore;

  ProjectResetService({
    required this.projectRoot,
    required this.snapshotStore,
  });

  Future<ProjectResetResult> reset() async {
    final normalizedRoot = p.normalize(p.absolute(projectRoot));
    final artifactRoots = await _discoverArtifactRoots(normalizedRoot);
    final relativePaths = <String>{};

    for (final root in artifactRoots) {
      final absoluteRoot = p.join(normalizedRoot, root);
      final entityType =
          FileSystemEntity.typeSync(absoluteRoot, followLinks: false);
      if (entityType == FileSystemEntityType.notFound) {
        continue;
      }
      if (entityType == FileSystemEntityType.file) {
        relativePaths.add(root);
        continue;
      }

      final directory = Directory(absoluteRoot);
      if (!await directory.exists()) {
        continue;
      }
      await for (final entity
          in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          relativePaths.add(p.relative(entity.path, from: normalizedRoot));
        }
      }
    }

    final deletedRoots = artifactRoots.where((root) {
      return FileSystemEntity.typeSync(
            p.join(normalizedRoot, root),
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound;
    }).toList()
      ..sort();

    final snapshot = await snapshotStore.createSnapshot(
      projectRoot: normalizedRoot,
      relativePaths: relativePaths.toList()..sort(),
      deletedDirectoryRoots: deletedRoots,
    );

    for (final root in deletedRoots.reversed) {
      final target = p.join(normalizedRoot, root);
      final type = FileSystemEntity.typeSync(target, followLinks: false);
      if (type == FileSystemEntityType.file) {
        await File(target).delete();
      } else if (type == FileSystemEntityType.directory) {
        await Directory(target).delete(recursive: true);
      }
    }

    return ProjectResetResult(
      snapshot: snapshot,
      deletedDirectoryRoots: deletedRoots,
    );
  }

  Future<ProjectResetUndoResult> undo() async {
    final snapshot =
        await snapshotStore.restoreLatestSnapshot(projectRoot: projectRoot);
    if (snapshot == null) {
      throw StateError('No reset snapshot found for $projectRoot');
    }
    return ProjectResetUndoResult(snapshot: snapshot);
  }

  Future<List<String>> _discoverArtifactRoots(String normalizedRoot) async {
    final config = await ShadcnConfig.load(normalizedRoot);
    final state = await ShadcnState.load(normalizedRoot);

    final installPath = config.installPath ?? state.installPath;
    final sharedPath = config.sharedPath ?? state.sharedPath;

    final roots = <String>{
      '.shadcn',
    };
    if (InlineActionJournal.journalFile(normalizedRoot).existsSync()) {
      roots.add('.shadcn');
    }
    if (installPath != null && installPath.trim().isNotEmpty) {
      roots.add(_normalizeProjectRelative(installPath));
    }
    if (sharedPath != null && sharedPath.trim().isNotEmpty) {
      final normalizedShared = _normalizeProjectRelative(sharedPath);
      final underInstall = installPath != null &&
          p.isWithin(_normalizeProjectRelative(installPath), normalizedShared);
      if (!underInstall) {
        roots.add(normalizedShared);
      }
    }

    return roots.toList();
  }

  String _normalizeProjectRelative(String rawPath) {
    final normalized = p.normalize(rawPath.trim());
    if (normalized == '.' || normalized == '..' || p.isAbsolute(normalized)) {
      throw ArgumentError.value(
          rawPath, 'rawPath', 'Path must be project-relative');
    }
    if (normalized.startsWith('../')) {
      throw ArgumentError.value(
          rawPath, 'rawPath', 'Path escapes project root');
    }
    return normalized;
  }
}
