import 'package:flutter_shadcn_cli/src/application/services/installer/dry_run_plan.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_component.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';

/// Converts a manifest `api` block into the lock's symbol summary.
///
/// List values are symbols; map values (`providedBy`/`reusedFrom`) contribute
/// their keys, matching `LockComponentApi.fromJson`.
LockComponentApi lockApiFor(ManifestApi api) {
  final byKind = <String, List<String>>{};
  api.groups.forEach((key, value) {
    if (value is List) {
      byKind[key] = value.whereType<String>().toList();
    } else if (value is Map) {
      byKind[key] = value.keys.map((entry) => entry.toString()).toList();
    }
  });
  return LockComponentApi(byKind: byKind);
}

/// Every symbol a manifest component declares.
Set<String> manifestSymbols(ManifestApi api) => lockApiFor(api).symbols;

/// Builds the lockfileVersion 2 delta for an install plan (plan §4).
///
/// Only components absent from [current] are recorded: re-adding an installed
/// component must never overwrite the hashes it recorded at install time.
class InstallLockBuilder {
  const InstallLockBuilder({
    required this.manifest,
    required this.installRoot,
    this.manifestSha256 = '',
  });

  final RegistryManifest manifest;
  final String installRoot;
  final String manifestSha256;

  ShadcnLock build(DryRunPlan plan, {required ShadcnLock current}) {
    var next = ShadcnLock(
      registry: ShadcnLockRegistry(
        name: manifest.registry.name,
        ref: manifest.registry.ref,
        manifestSha256: manifestSha256,
        generatedAt: manifest.registry.generatedAt,
      ),
      installRoot: installRoot,
    );

    next = next.mergeLayer(
      LockLayer.foundation,
      units: plan.foundation.toSet(),
      files: _layerFiles(plan, 'foundation'),
    );
    next = next.mergeLayer(
      LockLayer.theme,
      units: plan.theme.toSet(),
      files: _layerFiles(plan, 'theme'),
    );
    next = next.mergeLayer(
      LockLayer.primitives,
      units: plan.primitives.toSet(),
      files: _layerFiles(plan, 'primitives'),
    );

    for (final id in plan.components) {
      if (current.componentFor(id) != null) {
        continue;
      }
      final component = manifest.components[id]!;
      final files = <String, String>{};
      final userOwned = <String, String>{};
      for (final file in plan.files) {
        if (!_underComponent(file.source, id)) {
          continue;
        }
        if (file.userOwned) {
          if (file.sha256 != null &&
              (file.action == PlanAction.add ||
                  file.action == PlanAction.keep)) {
            userOwned[file.target] = file.sha256!;
          }
        } else if (file.sha256 != null && _recordable(file)) {
          files[file.target] = file.sha256!;
        }
      }
      next = next.upsertComponent(
        ShadcnLockComponent(
          id: id,
          files: files,
          userOwned: userOwned,
          deps: _lockDeps(component.deps),
          api: lockApiFor(component.api),
        ),
      );
    }

    for (final id in plan.blocks) {
      if (current.blockFor(id) != null) {
        continue;
      }
      final block = manifest.blocks[id]!;
      final files = <String, String>{};
      for (final file in plan.files) {
        if (!_underBlock(file.source, id)) {
          continue;
        }
        // A block owns no user-editable file: every path is registry-owned.
        if (!file.userOwned && file.sha256 != null && _recordable(file)) {
          files[file.target] = file.sha256!;
        }
      }
      next = next.upsertBlock(
        ShadcnLockBlock(
          id: id,
          files: files,
          deps: _lockDeps(block.deps),
        ),
      );
    }
    return next;
  }

  Map<String, String> _layerFiles(DryRunPlan plan, String layer) {
    final files = <String, String>{};
    for (final file in plan.files) {
      if (file.userOwned ||
          !file.source.startsWith('$layer/') ||
          file.sha256 == null ||
          !_recordable(file)) {
        continue;
      }
      files[file.target] = file.sha256!;
    }
    return files;
  }

  static bool _recordable(PlannedFile file) {
    return file.action == PlanAction.add ||
        file.action == PlanAction.update ||
        (file.action == PlanAction.skip && file.reason == 'identical');
  }

  static bool _underComponent(String source, String id) =>
      source.startsWith('components/$id/');

  static bool _underBlock(String source, String id) =>
      source.startsWith('blocks/$id/');

  static LockComponentDeps _lockDeps(ManifestComponentDeps deps) {
    return LockComponentDeps(
      foundation: _sorted(deps.foundation),
      theme: _sorted(deps.theme),
      primitives: _sorted(deps.primitives),
      components: _sorted(deps.components),
    );
  }

  static List<String> _sorted(Iterable<String> values) =>
      values.toSet().toList()..sort();
}
