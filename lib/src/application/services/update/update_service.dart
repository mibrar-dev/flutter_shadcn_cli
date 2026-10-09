import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer_file_install_part.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:path/path.dart' as p;

/// Outcome of `update` (P5_CLI_PLAN.md §2.3).
class UpdateReport {
  const UpdateReport({
    this.updated = const [],
    this.modified = const [],
    this.removedUpstream = const [],
    this.missing = const [],
    this.unchanged = const [],
    this.themeRegenerated = false,
    this.applied = true,
  });

  /// Registry-owned files overwritten with the manifest's current bytes.
  final List<String> updated;

  /// Files edited on disk: reported and skipped, never overwritten.
  final List<String> modified;

  /// Files the lock tracks that the manifest no longer declares.
  final List<String> removedUpstream;

  /// Files the lock tracks that are missing from disk and were restored.
  final List<String> missing;

  /// Files already identical to the manifest.
  final List<String> unchanged;

  final bool themeRegenerated;

  final bool applied;

  /// True when the install is behind, drifted or incomplete.
  bool get needsAttention =>
      updated.isNotEmpty || modified.isNotEmpty || removedUpstream.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'applied': applied,
        'themeRegenerated': themeRegenerated,
        'updated': updated,
        'modified': modified,
        'removedUpstream': removedUpstream,
        'missing': missing,
        'unchangedCount': unchanged.length,
        'needsAttention': needsAttention,
      };

  void writeHuman(CliLogger logger) {
    if (!needsAttention) {
      logger.success('Everything is up to date.');
    }
    if (updated.isNotEmpty) {
      logger.success('Updated ${updated.length} file(s).');
    }
    if (missing.isNotEmpty) {
      logger.warn('Restored ${missing.length} missing file(s).');
    }
    if (modified.isNotEmpty) {
      logger.warn(
        'Skipped ${modified.length} locally modified file(s): '
        '${modified.take(5).join(', ')}'
        '${modified.length > 5 ? ' …' : ''}',
      );
    }
    if (removedUpstream.isNotEmpty) {
      logger.warn(
        '${removedUpstream.length} file(s) were removed upstream and left '
        'in place: ${removedUpstream.take(5).join(', ')}'
        '${removedUpstream.length > 5 ? ' …' : ''}',
      );
    }
  }
}

/// Hash-driven `update`: overwrite unchanged registry files with the manifest's
/// current content, report locally modified files, and never touch user-owned
/// `<name>_theme.dart` files (plan §2.3).
class UpdateService {
  const UpdateService({
    required this.manifest,
    required this.reader,
    required this.projectRoot,
    required this.installRoot,
    this.manifestSha256 = '',
    this.themeRegenerator,
  });

  final RegistryManifest manifest;
  final RegistryFileReader reader;

  /// Absolute project root.
  final String projectRoot;

  /// Project-relative install root recorded by the lock (or the manifest).
  final String installRoot;

  final String manifestSha256;

  /// Re-renders `theme/app_theme.dart` for a preset id. Injected by the command
  /// (B6's theme service) so this service stays independent of the theme flow.
  final Future<void> Function(String presetId)? themeRegenerator;

  ShadcnLockRepository get _lockRepo => ShadcnLockRepository(projectRoot);

  Future<UpdateReport> run({
    Set<String>? componentIds,
    bool check = false,
  }) async {
    final lock = await _lockRepo.load();
    final root = lock.installRoot.isEmpty ? installRoot : lock.installRoot;
    final themePath = lock.theme?.path;

    final updated = <String>[];
    final modified = <String>[];
    final removedUpstream = <String>[];
    final missing = <String>[];
    final unchanged = <String>[];
    final newHashes = <String, String>{};

    final tracked = _trackedRegistryFiles(lock, componentIds);
    for (final entry in tracked.entries) {
      final target = entry.key;
      if (themePath != null && target == themePath) {
        continue;
      }
      final source = _sourceFor(target, root);
      if (source == null) {
        continue;
      }
      if (!manifest.declaredFiles.contains(source)) {
        removedUpstream.add(target);
        continue;
      }
      final bytes = await reader.readBytes(source);
      if (bytes == null) {
        removedUpstream.add(target);
        continue;
      }
      final newSha = FileHashing.ofBytes(bytes);
      final disk = File(p.join(projectRoot, target));
      final diskSha = await FileHashing.ofFileIfExists(disk);
      if (diskSha == null) {
        missing.add(target);
        newHashes[target] = newSha;
        if (!check) {
          await _write(disk, bytes);
        }
      } else if (FileHashing.matches(entry.value, diskSha)) {
        if (diskSha == newSha) {
          unchanged.add(target);
        } else {
          updated.add(target);
          newHashes[target] = newSha;
          if (!check) {
            await _write(disk, bytes);
          }
        }
      } else {
        modified.add(target);
      }
    }

    var themeRegenerated = false;
    if (!check && newHashes.isNotEmpty) {
      await _lockRepo.save(_applyHashes(lock, newHashes));
    }
    if (!check) {
      themeRegenerated = await _regenerateTheme(lock);
    }

    return UpdateReport(
      updated: _sorted(updated),
      modified: _sorted(modified),
      removedUpstream: _sorted(removedUpstream),
      missing: _sorted(missing),
      unchanged: _sorted(unchanged),
      themeRegenerated: themeRegenerated,
      applied: !check,
    );
  }

  /// Re-renders `<installRoot>/theme/app_theme.dart` from the locked preset.
  ///
  /// B6 owns the theme service; `update` only asks it to refresh. Returns
  /// false when there is no locked theme (nothing to do).
  Future<bool> _regenerateTheme(ShadcnLock lock) async {
    final themeId = lock.theme?.id;
    final regenerate = themeRegenerator;
    if (themeId == null || themeId.isEmpty || regenerate == null) {
      return false;
    }
    await regenerate(themeId);
    return true;
  }

  Map<String, String> _trackedRegistryFiles(
    ShadcnLock lock,
    Set<String>? componentIds,
  ) {
    final result = <String, String>{};
    for (final layer in LockLayer.values) {
      result.addAll(lock.layerState(layer).files);
    }
    for (final component in lock.components) {
      if (componentIds != null && !componentIds.contains(component.id)) {
        continue;
      }
      result.addAll(component.files);
    }
    return result;
  }

  /// Maps a project-relative target back to its registry-relative source.
  String? _sourceFor(String target, String root) {
    final normalizedTarget = normalizeLockPath(target);
    final prefix = root.isEmpty ? '' : '${normalizeLockPath(root)}/';
    if (prefix.isNotEmpty && normalizedTarget.startsWith(prefix)) {
      return normalizedTarget.substring(prefix.length);
    }
    return null;
  }

  ShadcnLock _applyHashes(ShadcnLock lock, Map<String, String> newHashes) {
    var next = lock;
    for (final layer in LockLayer.values) {
      final state = lock.layerState(layer);
      final files = {...state.files};
      var changed = false;
      for (final entry in newHashes.entries) {
        if (files.containsKey(entry.key)) {
          files[entry.key] = entry.value;
          changed = true;
        }
      }
      if (changed) {
        next = next.putLayer(
          layer,
          LockLayerState(units: state.units, files: files),
        );
      }
    }
    for (final component in lock.components) {
      final files = {...component.files};
      var changed = false;
      for (final entry in newHashes.entries) {
        if (files.containsKey(entry.key)) {
          files[entry.key] = entry.value;
          changed = true;
        }
      }
      if (changed) {
        next = next.upsertComponent(component.copyWith(files: files));
      }
    }
    if (manifestSha256.isNotEmpty) {
      next = next.withRegistry(
        lock.registry.copyWith(manifestSha256: manifestSha256),
      );
    }
    return next;
  }

  Future<void> _write(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  static List<String> _sorted(Iterable<String> values) =>
      values.toSet().toList()..sort();
}
