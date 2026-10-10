import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/application/services/manifest_closure.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:path/path.dart' as p;

/// Outcome of `remove`.
class RemoveReport {
  const RemoveReport({
    required this.requested,
    this.removed = const [],
    this.removedBlocks = const [],
    this.skipped = const [],
    this.refused = const [],
    this.dependents = const {},
    this.deletedFiles = const [],
    this.keptUserOwned = const [],
    this.applied = true,
  });

  final List<String> requested;

  /// Component ids removed.
  final List<String> removed;

  /// Block ids removed.
  final List<String> removedBlocks;

  /// Requested ids that were not installed.
  final List<String> skipped;

  /// Requested ids still required by other installed components or blocks
  /// (no `--force`).
  final List<String> refused;

  /// refused id -> the components and blocks that still need it.
  final Map<String, List<String>> dependents;

  /// Project-relative paths deleted (component + block + orphaned layer
  /// files).
  final List<String> deletedFiles;

  /// User-owned paths left in place.
  final List<String> keptUserOwned;

  final bool applied;

  Map<String, dynamic> toJson() {
    return {
      'requested': requested,
      'removed': removed,
      'removedBlocks': removedBlocks,
      'skipped': skipped,
      'refused': refused,
      'dependents': dependents,
      'deletedFiles': deletedFiles,
      'keptUserOwned': keptUserOwned,
      'applied': applied,
    };
  }

  void writeHuman(CliLogger logger) {
    if (removed.isEmpty &&
        removedBlocks.isEmpty &&
        refused.isEmpty &&
        skipped.isEmpty) {
      logger.info('Nothing to remove.');
      return;
    }
    for (final id in removed) {
      logger.success('Removed $id (${deletedFiles.length} files total)');
    }
    for (final id in removedBlocks) {
      logger.success('Removed block $id');
    }
    for (final id in refused) {
      logger.warn(
        'Cannot remove $id; required by ${dependents[id]!.join(', ')} '
        '(re-run with --force to remove anyway)',
      );
    }
    for (final id in skipped) {
      logger.detail('Skipping $id (not installed)');
    }
    if (keptUserOwned.isNotEmpty) {
      logger.info('  user-owned files kept: ${keptUserOwned.join(', ')}');
    }
  }
}

/// Removes components and blocks and prunes layer units no remaining install
/// needs.
///
/// User-owned `<name>_theme.dart` files are never deleted unless
/// `purgeUserThemes` is set (plan §1.5, §4). A block owns no user-owned file,
/// so `remove <block>` always deletes every path it recorded.
class InstallerRemover {
  InstallerRemover({
    required this.manifest,
    required this.projectRoot,
    CliLogger? logger,
  }) : logger = logger ?? CliLogger();

  final RegistryManifest manifest;

  /// Absolute project root.
  final String projectRoot;

  final CliLogger logger;

  ShadcnLockRepository get _lockRepo => ShadcnLockRepository(projectRoot);

  Future<RemoveReport> remove(
    Iterable<String> componentIds, {
    bool force = false,
    bool purgeUserThemes = false,
    bool dryRun = false,
  }) async {
    final requested = [
      for (final id in componentIds)
        if (id.trim().isNotEmpty) id.trim(),
    ];
    final lock = await _lockRepo.load();
    final installedComponents = {
      for (final component in lock.components) component.id,
    };
    final installedBlocks = {for (final block in lock.blocks) block.id};

    final skipped = [
      for (final id in requested)
        if (!installedComponents.contains(id) && !installedBlocks.contains(id))
          id,
    ];
    final candidates = [
      for (final id in requested)
        if (installedComponents.contains(id) || installedBlocks.contains(id))
          id,
    ];
    final candidateSet = candidates.toSet();

    // Anything still referencing a candidate blocks its removal, including a
    // block that needs the component ("cannot remove button; required by
    // login-01").
    final dependents = <String, List<String>>{};
    for (final id in candidates) {
      final list = <String>{
        for (final component in lock.components)
          if (!candidateSet.contains(component.id) &&
              component.deps.components.contains(id))
            component.id,
        for (final block in lock.blocks)
          if (!candidateSet.contains(block.id) &&
              block.deps.components.contains(id))
            block.id,
      }.toList()
        ..sort();
      if (list.isNotEmpty) {
        dependents[id] = list;
      }
    }

    final refused = (!force && dependents.isNotEmpty)
        ? (dependents.keys.toList()..sort())
        : <String>[];
    final effective = {
      for (final id in candidates)
        if (!refused.contains(id)) id,
    };
    final removedComponents = [
      for (final id in effective)
        if (installedComponents.contains(id)) id,
    ];
    final removedBlocks = [
      for (final id in effective)
        if (installedBlocks.contains(id)) id,
    ];

    final remaining = [
      for (final component in lock.components)
        if (!effective.contains(component.id)) component,
    ];
    final remainingBlocks = [
      for (final block in lock.blocks)
        if (!effective.contains(block.id)) block,
    ];

    // Layer units the remaining installs still need: the manifest closure of
    // the remaining components and blocks, plus each remaining record's own
    // deps (so a component missing from a moved registry is not
    // under-counted).
    final closure = ManifestClosureResolver(manifest).resolve(
      remaining.map((component) => component.id),
      blockIds: remainingBlocks.map((block) => block.id),
      includeCore: true,
    );
    final neededUnits = <LockLayer, Set<String>>{
      for (final layer in LockLayer.values) layer: <String>{},
    };
    neededUnits[LockLayer.foundation]!.addAll(closure.foundation);
    neededUnits[LockLayer.theme]!.addAll(closure.theme);
    neededUnits[LockLayer.primitives]!.addAll(closure.primitives);
    for (final component in remaining) {
      neededUnits[LockLayer.foundation]!.addAll(component.deps.foundation);
      neededUnits[LockLayer.theme]!.addAll(component.deps.theme);
      neededUnits[LockLayer.primitives]!.addAll(component.deps.primitives);
    }
    for (final block in remainingBlocks) {
      neededUnits[LockLayer.foundation]!.addAll(block.deps.foundation);
      neededUnits[LockLayer.theme]!.addAll(block.deps.theme);
      neededUnits[LockLayer.primitives]!.addAll(block.deps.primitives);
    }

    final installRoot =
        lock.installRoot.isEmpty ? manifest.install.root : lock.installRoot;
    final containing = _containingUnits(installRoot);
    final remainingOwned = <String>{
      for (final component in remaining) ...component.files.keys,
      for (final component in remaining) ...component.userOwned.keys,
      for (final block in remainingBlocks) ...block.files.keys,
    };

    final targets = <String>{};
    final keptUserOwned = <String>[];
    for (final id in removedComponents) {
      final component = lock.componentFor(id)!;
      targets.addAll(component.files.keys);
      if (purgeUserThemes) {
        targets.addAll(component.userOwned.keys);
      } else {
        keptUserOwned.addAll(component.userOwned.keys);
      }
    }
    for (final id in removedBlocks) {
      targets.addAll(lock.blockFor(id)!.files.keys);
    }

    // Orphan layer files: known to the manifest, no remaining unit needs them,
    // and no remaining component owns them.
    for (final layer in LockLayer.values) {
      for (final path in lock.layerState(layer).files.keys) {
        final units = containing[layer]?[path] ?? const <String>{};
        final orphan = units.isNotEmpty &&
            units.every((unit) => !neededUnits[layer]!.contains(unit));
        if (orphan && !remainingOwned.contains(path)) {
          targets.add(path);
        }
      }
    }

    final deleted = <String>[];
    if (!dryRun) {
      for (final target in targets.toList()..sort()) {
        final file = File(p.join(projectRoot, target));
        if (await file.exists()) {
          await file.delete();
          deleted.add(target);
        }
      }
      var next = lock;
      for (final id in removedComponents) {
        next = next.removeComponent(id);
      }
      for (final id in removedBlocks) {
        next = next.removeBlock(id);
      }
      for (final layer in LockLayer.values) {
        final oldState = lock.layerState(layer);
        final files = <String, String>{};
        oldState.files.forEach((path, sha) {
          final units = containing[layer]?[path] ?? const <String>{};
          final orphan = units.isNotEmpty &&
              units.every((unit) => !neededUnits[layer]!.contains(unit));
          if (!orphan) {
            files[path] = sha;
          }
        });
        next = next.putLayer(
          layer,
          LockLayerState(
            units: lockSortedList(neededUnits[layer]!),
            files: files,
          ),
        );
      }
      await _lockRepo.save(next);
    }

    return RemoveReport(
      requested: requested,
      removed: removedComponents..sort(),
      removedBlocks: removedBlocks..sort(),
      skipped: skipped..sort(),
      refused: refused,
      dependents: dependents,
      deletedFiles: deleted,
      keptUserOwned: keptUserOwned..sort(),
      applied: !dryRun,
    );
  }

  /// layer -> project-relative target -> the manifest units that declare it.
  Map<LockLayer, Map<String, Set<String>>> _containingUnits(
      String installRoot) {
    final result = <LockLayer, Map<String, Set<String>>>{
      for (final layer in LockLayer.values) layer: <String, Set<String>>{},
    };
    void index(LockLayer layer, Map<String, List<String>> units) {
      units.forEach((unit, files) {
        for (final file in files) {
          final target = p.posix.join(installRoot, file);
          result[layer]!.putIfAbsent(target, () => <String>{}).add(unit);
        }
      });
    }

    index(LockLayer.foundation, {
      for (final entry in manifest.foundation.entries)
        entry.key: entry.value.files,
    });
    index(LockLayer.theme, {
      for (final entry in manifest.theme.entries) entry.key: entry.value.files,
    });
    index(LockLayer.primitives, {
      for (final entry in manifest.primitives.entries)
        entry.key: entry.value.files,
    });
    return result;
  }
}
