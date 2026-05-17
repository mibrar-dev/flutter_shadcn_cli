part of 'installer.dart';

extension InstallerRemovePart on Installer {
  Future<void> removeComponent(String name, {bool force = false}) async {
    await ensureInitFiles(allowPrompts: false);
    await _ensureConfigLoaded();
    final component = await _manifestResolver.resolve(name);
    if (component == null) {
      logger.warn('Component "$name" not found');
      return;
    }

    final installed = await _installedComponentIds();
    if (!installed.contains(component.id)) {
      logger.detail('Skipping ${component.id} (not installed)');
      return;
    }

    final dependents = await _dependentComponents(component.id, installed);
    if (dependents.isNotEmpty && !force) {
      logger.warn(
        'Cannot remove ${component.id}; required by ${dependents.join(', ')}',
      );
      return;
    }

    logger.action('Removing ${component.name} (${component.id})');
    for (final file in component.files) {
      final destination = _resolveComponentDestination(component, file);
      final targetFile = File(destination);
      if (await targetFile.exists()) {
        await targetFile.delete();
        _cleanupEmptyParents(targetFile.parent, component.id);
      }
    }
    await _removeComponentManifest(component.id);

    _installedComponentCache?.remove(component.id);
    if (!_deferAliases) {
      await generateAliases();
    }
    if (!_deferComponentManifest) {
      await _updateComponentManifest();
      await _updateState();
    }
    if (!_deferDependencyUpdates) {
      await _syncDependenciesWithInstalled();
    }
  }

  Future<void> removeAllComponents({bool force = true}) async {
    await ensureInitFiles(allowPrompts: false);
    await _ensureConfigLoaded();
    final managedDeps = await _loadManagedDependencies();
    final installed = await _installedComponentIds();
    if (installed.isEmpty) {
      logger.info('No installed components to remove.');
      await _removeAllInstallArtifacts();
      _installedComponentCache = null;
      if (!_deferDependencyUpdates) {
        await _syncDependenciesWithInstalled(
          installedOverride: const {},
          managedOverride: managedDeps,
        );
      }
      return;
    }
    if (!_deferDependencyUpdates) {
      await _syncDependenciesWithInstalled(
        installedOverride: const {},
        managedOverride: managedDeps,
      );
    }
    await runBulkInstall(() async {
      for (final id in installed.toList()) {
        await removeComponent(id, force: force);
      }
    });
    await _removeAllInstallArtifacts();
    _installedComponentCache = null;
  }

  Future<void> _removeAllInstallArtifacts() async {
    final config = _cachedConfig ?? const ShadcnConfig();
    final installRoot = Directory(_resolveProjectPath(_installPath(config)));
    final sharedRoot = Directory(_resolveProjectPath(_sharedPath(config)));
    final configRoot = Directory(_resolveProjectPath('.shadcn'));

    if (installRoot.existsSync()) {
      await installRoot.delete(recursive: true);
    }
    if (sharedRoot.existsSync()) {
      await sharedRoot.delete(recursive: true);
    }
    if (configRoot.existsSync()) {
      await configRoot.delete(recursive: true);
    }

    final installPath = _installPath(config);
    final parts = p.split(installPath);
    for (var i = parts.length - 1; i >= 0; i--) {
      final parentPath = p.joinAll(parts.sublist(0, i + 1));
      final parentDir = Directory(_resolveProjectPath(parentPath));
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

  Future<Set<String>> _installedComponentIds() async {
    await _ensureConfigLoaded();
    if (_installedComponentCache != null) {
      return _installedComponentCache!;
    }
    final installPath = _installPath(_cachedConfig);
    final componentsDir =
        Directory(_resolveProjectPath(p.join(installPath, 'components')));
    final compositesDir = enableComposites
        ? Directory(_resolveProjectPath(p.join(installPath, 'composites')))
        : null;
    if (!componentsDir.existsSync() &&
        (compositesDir == null || !compositesDir.existsSync())) {
      _installedComponentCache = {};
      return _installedComponentCache!;
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
    _installedComponentCache = installed;
    return installed;
  }

  Future<List<String>> _dependentComponents(
      String id, Set<String> installed) async {
    final dependents = <String>[];
    for (final installedId in installed) {
      if (installedId == id) {
        continue;
      }
      final component = await _manifestResolver.resolve(installedId);
      if (component != null && component.dependsOn.contains(id)) {
        dependents.add(installedId);
      }
    }
    return dependents;
  }

  void _cleanupEmptyParents(Directory dir, String componentId) {
    final installPath = _installPath(_cachedConfig);
    final componentRoot = p.normalize(
      p.join(targetDir, installPath, 'components'),
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
