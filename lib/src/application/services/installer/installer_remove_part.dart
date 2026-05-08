part of 'installer.dart';

extension InstallerRemovePart on Installer {
  InstallerRemoveService _removeService() {
    return InstallerRemoveService(
      registry: registry,
      targetDir: targetDir,
      logger: logger,
      enableComposites: enableComposites,
      ensureInitFiles: ensureInitFiles,
      ensureConfigLoaded: _ensureConfigLoaded,
      cachedConfig: () => _cachedConfig,
      installedComponentCache: () => _installedComponentCache,
      setInstalledComponentCache: (value) => _installedComponentCache = value,
      deferAliases: () => _deferAliases,
      deferComponentManifest: () => _deferComponentManifest,
      deferDependencyUpdates: () => _deferDependencyUpdates,
      lockfileComponentRecord: _lockfileComponentRecord,
      loadManagedDependencies: _loadManagedDependencies,
      lockfilePathOwnedByOther: _lockfilePathOwnedByOther,
      resolveProjectPath: _resolveProjectPath,
      installPath: _installPath,
      sharedPath: _sharedPath,
      resolveComponentDestination: _resolveComponentDestination,
      removeLocaleResources: _removeLocaleResources,
      removeComponentManifest: _removeComponentManifest,
      removeLockfileRecord: _removeLockfileRecord,
      generateAliases: generateAliases,
      updateComponentManifest: _updateComponentManifest,
      updateState: _updateState,
      syncDependenciesWithInstalled: _syncDependenciesWithInstalled,
      runBulkInstall: runBulkInstall,
    );
  }

  Future<void> removeComponent(String name, {bool force = false}) async {
    await _removeService().removeComponent(name, force: force);
  }

  Future<void> removeAllComponents({bool force = true}) async {
    await _removeService().removeAllComponents(force: force);
  }

  Future<Set<String>> _installedComponentIds() async {
    return _removeService().installedComponentIds();
  }
}
