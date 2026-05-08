import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;

typedef InstallerSyncDependencies = Future<void> Function({
  Set<String>? installedOverride,
  Set<String>? managedOverride,
});

class InstallerRemoveService {
  final Registry registry;
  final String targetDir;
  final CliLogger logger;
  final bool enableComposites;
  final Future<void> Function({required bool allowPrompts}) ensureInitFiles;
  final Future<void> Function() ensureConfigLoaded;
  final ShadcnConfig? Function() cachedConfig;
  final Set<String>? Function() installedComponentCache;
  final void Function(Set<String>? value) setInstalledComponentCache;
  final bool Function() deferAliases;
  final bool Function() deferComponentManifest;
  final bool Function() deferDependencyUpdates;
  final Future<ShadcnLockComponent?> Function(String componentId)
      lockfileComponentRecord;
  final Future<Set<String>> Function() loadManagedDependencies;
  final Future<bool> Function({
    required String relativePath,
    required String componentId,
  }) lockfilePathOwnedByOther;
  final String Function(String relativePath) resolveProjectPath;
  final String Function(ShadcnConfig? config) installPath;
  final String Function(ShadcnConfig? config) sharedPath;
  final String Function(Component component, RegistryFile file)
      resolveComponentDestination;
  final Future<void> Function(String componentId) removeLocaleResources;
  final Future<void> Function(String componentId) removeComponentManifest;
  final Future<void> Function(String componentId) removeLockfileRecord;
  final Future<void> Function() generateAliases;
  final Future<void> Function() updateComponentManifest;
  final Future<void> Function() updateState;
  final InstallerSyncDependencies syncDependenciesWithInstalled;
  final Future<void> Function(Future<void> Function() action) runBulkInstall;

  const InstallerRemoveService({
    required this.registry,
    required this.targetDir,
    required this.logger,
    required this.enableComposites,
    required this.ensureInitFiles,
    required this.ensureConfigLoaded,
    required this.cachedConfig,
    required this.installedComponentCache,
    required this.setInstalledComponentCache,
    required this.deferAliases,
    required this.deferComponentManifest,
    required this.deferDependencyUpdates,
    required this.lockfileComponentRecord,
    required this.loadManagedDependencies,
    required this.lockfilePathOwnedByOther,
    required this.resolveProjectPath,
    required this.installPath,
    required this.sharedPath,
    required this.resolveComponentDestination,
    required this.removeLocaleResources,
    required this.removeComponentManifest,
    required this.removeLockfileRecord,
    required this.generateAliases,
    required this.updateComponentManifest,
    required this.updateState,
    required this.syncDependenciesWithInstalled,
    required this.runBulkInstall,
  });

  Future<void> removeComponent(String name, {bool force = false}) async {
    await ensureInitFiles(allowPrompts: false);
    await ensureConfigLoaded();
    final component = registry.getComponent(name);
    if (component == null) {
      logger.warn('Component "$name" not found');
      return;
    }

    final lockRecord = await lockfileComponentRecord(component.id);
    final installed = await installedComponentIds();
    final managedDepsBeforeRemove = {
      ...await loadManagedDependencies(),
      if (lockRecord != null) ...lockRecord.dependencies.keys,
    };
    if (!installed.contains(component.id) && lockRecord == null) {
      logger.detail('Skipping ${component.id} (not installed)');
      return;
    }

    final dependents = dependentComponents(component.id, installed);
    if (dependents.isNotEmpty && !force) {
      logger.warn(
        'Cannot remove ${component.id}; required by ${dependents.join(', ')}',
      );
      return;
    }

    logger.action('Removing ${component.name} (${component.id})');
    await removeLocaleResources(component.id);
    if (lockRecord != null) {
      for (final relativePath in lockRecord.installedFiles) {
        if (await lockfilePathOwnedByOther(
          relativePath: relativePath,
          componentId: component.id,
        )) {
          continue;
        }
        final targetFile = File(resolveProjectPath(relativePath));
        if (await targetFile.exists()) {
          await targetFile.delete();
          cleanupEmptyParents(targetFile.parent, component.id);
        }
      }
    } else {
      for (final file in component.files) {
        final destination = resolveComponentDestination(component, file);
        final targetFile = File(destination);
        if (await targetFile.exists()) {
          await targetFile.delete();
          cleanupEmptyParents(targetFile.parent, component.id);
        }
      }
    }
    await removeComponentManifest(component.id);
    await removeLockfileRecord(component.id);

    installedComponentCache()?.remove(component.id);
    if (!deferAliases()) {
      await generateAliases();
    }
    if (!deferComponentManifest()) {
      await updateComponentManifest();
      await updateState();
    }
    if (!deferDependencyUpdates()) {
      await syncDependenciesWithInstalled(
        managedOverride: managedDepsBeforeRemove,
      );
    }
  }

  Future<void> removeAllComponents({bool force = true}) async {
    await ensureInitFiles(allowPrompts: false);
    await ensureConfigLoaded();
    final managedDeps = await loadManagedDependencies();
    final installed = await installedComponentIds();
    if (installed.isEmpty) {
      logger.info('No installed components to remove.');
      await removeAllInstallArtifacts();
      setInstalledComponentCache(null);
      if (!deferDependencyUpdates()) {
        await syncDependenciesWithInstalled(
          installedOverride: const {},
          managedOverride: managedDeps,
        );
      }
      return;
    }
    if (!deferDependencyUpdates()) {
      await syncDependenciesWithInstalled(
        installedOverride: const {},
        managedOverride: managedDeps,
      );
    }
    await runBulkInstall(() async {
      for (final id in installed.toList()) {
        await removeComponent(id, force: force);
      }
    });
    await removeAllInstallArtifacts();
    setInstalledComponentCache(null);
  }

  Future<void> removeAllInstallArtifacts() async {
    final config = cachedConfig() ?? const ShadcnConfig();
    final installRoot = Directory(resolveProjectPath(installPath(config)));
    final sharedRoot = Directory(resolveProjectPath(sharedPath(config)));
    final configRoot = Directory(resolveProjectPath('.shadcn'));

    if (installRoot.existsSync()) {
      await installRoot.delete(recursive: true);
    }
    if (sharedRoot.existsSync()) {
      await sharedRoot.delete(recursive: true);
    }
    if (configRoot.existsSync()) {
      await configRoot.delete(recursive: true);
    }
    final lockfile = File(resolveProjectPath('shadcn.lock'));
    if (lockfile.existsSync()) {
      await lockfile.delete();
    }

    final installPathValue = installPath(config);
    final parts = p.split(installPathValue);
    for (var i = parts.length - 1; i >= 0; i--) {
      final parentPath = p.joinAll(parts.sublist(0, i + 1));
      final parentDir = Directory(resolveProjectPath(parentPath));
      if (parentDir.existsSync()) {
        final contents = parentDir.listSync();
        if (contents.isEmpty) {
          await parentDir.delete();
          logger.detail('Removed empty directory: $parentPath');
        } else {
          break;
        }
      }
    }
  }

  Future<Set<String>> installedComponentIds() async {
    await ensureConfigLoaded();
    final cache = installedComponentCache();
    if (cache != null) {
      return cache;
    }
    final installPathValue = installPath(cachedConfig());
    final componentsDir = Directory(
      resolveProjectPath(p.join(installPathValue, 'components')),
    );
    final compositesDir = enableComposites
        ? Directory(resolveProjectPath(p.join(installPathValue, 'composites')))
        : null;
    if (!componentsDir.existsSync() &&
        (compositesDir == null || !compositesDir.existsSync())) {
      final installed = <String>{};
      setInstalledComponentCache(installed);
      return installed;
    }

    final installed = <String>{};
    final dirs = <Directory>[];
    if (componentsDir.existsSync()) {
      dirs.add(componentsDir);
    }
    if (compositesDir != null && compositesDir.existsSync()) {
      dirs.add(compositesDir);
    }
    for (final dir in dirs) {
      for (final entry in dir.listSync(recursive: true)) {
        if (entry is! File || !entry.path.endsWith('meta.json')) {
          continue;
        }
        try {
          final content = await entry.readAsString();
          final data = jsonDecode(content) as Map<String, dynamic>;
          final id = data['id']?.toString();
          if (id != null && id.isNotEmpty) {
            installed.add(id);
          }
        } catch (_) {}
      }
    }
    setInstalledComponentCache(installed);
    return installed;
  }

  List<String> dependentComponents(String id, Set<String> installed) {
    final dependents = <String>[];
    for (final installedId in installed) {
      if (installedId == id) {
        continue;
      }
      final component = registry.getComponent(installedId);
      if (component != null && component.dependsOn.contains(id)) {
        dependents.add(installedId);
      }
    }
    return dependents;
  }

  void cleanupEmptyParents(Directory dir, String componentId) {
    final installPathValue = installPath(cachedConfig());
    final componentRoot = p.normalize(
      p.join(targetDir, installPathValue, 'components'),
    );
    var current = dir;
    while (p.normalize(current.path).startsWith(componentRoot)) {
      if (current.listSync().isNotEmpty) {
        break;
      }
      if (p.normalize(current.path) == componentRoot) {
        break;
      }
      current.deleteSync();
      current = current.parent;
    }
  }
}
