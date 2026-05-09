part of 'installer.dart';

extension InstallerSharedPart on Installer {
  Future<void> installShared(String id) async {
    await _sharedService.installShared(
      id,
      ensureConfigLoaded: _ensureConfigLoaded,
      installComponent: addComponent,
      installFileWithDependencies: _installFileWithDependencies,
    );
  }

  Future<void> ensureInitFiles({bool allowPrompts = false}) async {
    if (_initFilesEnsured) {
      return;
    }
    _initFilesEnsured = true;
    final configFile = ShadcnConfig.configFile(targetDir);
    final hasConfig = await configFile.exists();
    if (!hasConfig) {
      if (allowPrompts) {
        await _ensureConfig();
      } else {
        await _ensureConfigDefaults();
      }
    } else {
      await _ensureConfigLoaded();
    }
  }

  Future<void> runBulkInstall(Future<void> Function() action) async {
    final previousAlias = _deferAliases;
    final previousDeps = _deferDependencyUpdates;
    final previousManifest = _deferComponentManifest;
    _deferAliases = true;
    _deferDependencyUpdates = true;
    _deferComponentManifest = true;
    try {
      await action();
    } finally {
      _deferAliases = previousAlias;
      _deferDependencyUpdates = previousDeps;
      _deferComponentManifest = previousManifest;
      if (_pendingDependencies.isNotEmpty) {
        final pending = Map<String, dynamic>.from(_pendingDependencies);
        _pendingDependencies.clear();
        await _updateDependencies(pending);
      }
      if (_pendingAssets.isNotEmpty) {
        final pending = _pendingAssets.toList()..sort();
        _pendingAssets.clear();
        await _updateAssets(pending);
      }
      if (_pendingFonts.isNotEmpty) {
        final pending = List<FontEntry>.from(_pendingFonts);
        _pendingFonts.clear();
        await _updateFonts(pending);
      }
      await _syncDependenciesWithInstalled();
      if (!_deferAliases) {
        await generateAliases();
      }
      if (!_deferComponentManifest) {
        await _updateComponentManifest();
      }
      await _updateState();
    }
  }

  Future<void> _queueDependencyUpdates(Map<String, dynamic> deps) async {
    if (!_deferDependencyUpdates) {
      await _updateDependencies(deps);
      return;
    }
    deps.forEach((key, value) {
      if (value != null) {
        _pendingDependencies[key] = value;
      }
    });
  }

  Future<void> _queueAssetUpdates(List<String> assets) async {
    if (assets.isEmpty) {
      return;
    }
    if (!_deferDependencyUpdates) {
      await _updateAssets(assets);
      return;
    }
    _pendingAssets.addAll(assets);
  }

  Future<void> _queueFontUpdates(List<FontEntry> fonts) async {
    if (fonts.isEmpty) {
      return;
    }
    if (!_deferDependencyUpdates) {
      await _updateFonts(fonts);
      return;
    }
    _pendingFonts.addAll(fonts);
  }

  List<String> _coreSharedIdsForInit() {
    return _sharedService.coreSharedIdsForInit();
  }

  String _normalizeSharedId(String id) {
    return _sharedService.normalizeSharedId(id);
  }

  Future<Set<String>> _resolveSharedDependencyClosure(
    Set<String> seedIds,
  ) async {
    return _sharedService.resolveSharedDependencyClosure(seedIds);
  }

  InstallerRegistryFileOwner? _lookupRegistryFileOwner(String source) {
    return _sharedService.lookupRegistryFileOwner(source);
  }

  String _normalizeRegistryPath(String source) {
    return _sharedService.normalizeRegistryPath(source);
  }
}
