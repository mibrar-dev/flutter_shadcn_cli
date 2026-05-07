part of 'installer.dart';

extension InstallerSharedPart on Installer {
  Future<void> installShared(String id) async {
    await _ensureConfigLoaded();
    final resolvedId = _normalizeSharedId(id);
    final sharedMatches = registry.shared.where((s) => s.id == resolvedId);
    if (sharedMatches.isEmpty) {
      final fallbackComponent = registry.getComponent(resolvedId);
      if (fallbackComponent != null) {
        await addComponent(resolvedId);
        return;
      }
      logger.warn('Shared item "$id" not found');
      return;
    }
    final sharedItem = sharedMatches.first;

    if (_installedSharedCache.contains(resolvedId) ||
        _installingSharedIds.contains(resolvedId)) {
      return;
    }

    _installingSharedIds.add(resolvedId);
    try {
      final sharedDeps = await _loadSharedDependencies(resolvedId);
      for (final depId in sharedDeps) {
        if (depId == resolvedId) {
          continue;
        }
        await installShared(depId);
      }
      for (final file in sharedItem.files) {
        await _installFileWithDependencies(
          file,
          sharedItem.files,
          sharedId: sharedItem.id,
        );
      }

      _installedSharedCache.add(resolvedId);
    } finally {
      _installingSharedIds.remove(resolvedId);
    }
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
      if (!_suppressDependencySync) {
        await _syncDependenciesWithInstalled();
      }
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
    final ids = <String>[
      'theme',
      'util',
      'color_extensions',
      'form_control',
      'form_value_supplier',
    ];
    final hasColorScheme =
        registry.shared.any((shared) => shared.id == 'color_scheme');
    if (hasColorScheme) {
      ids.add('color_scheme');
    }
    return ids;
  }

  String _normalizeSharedId(String id) {
    switch (id) {
      case 'utils':
        return 'util';
      default:
        return id;
    }
  }

  Future<Set<String>> _resolveSharedDependencyClosure(
      Set<String> seedIds) async {
    final resolved = <String>{};
    final pending = <String>[];
    for (final id in seedIds) {
      pending.add(_normalizeSharedId(id));
    }
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!resolved.add(id)) {
        continue;
      }
      final deps = await _loadSharedDependencies(id);
      for (final dep in deps) {
        final normalized = _normalizeSharedId(dep);
        if (!resolved.contains(normalized)) {
          pending.add(normalized);
        }
      }
    }
    return resolved;
  }

  Future<Set<String>> _loadSharedDependencies(String sharedId) async {
    final cached = _sharedDependencyCache[sharedId];
    if (cached != null) {
      return cached;
    }

    final matches = registry.shared.where((s) => s.id == sharedId);
    if (matches.isEmpty) {
      _sharedDependencyCache[sharedId] = {};
      return {};
    }

    final deps = <String>{};
    final sharedItem = matches.first;
    for (final file in sharedItem.files) {
      if (!file.source.endsWith('.dart')) {
        continue;
      }
      try {
        final bytes = await registry.readSourceBytes(file.source);
        final content = utf8.decode(bytes);
        final dir = p.posix.dirname(_normalizeRegistryPath(file.source));
        for (final line in content.split('\n')) {
          if (_partOfDirectiveRegex.hasMatch(line)) {
            continue;
          }
          final match = _importDirectiveRegex.firstMatch(line);
          if (match == null) {
            continue;
          }
          final importPath = match.group(2);
          if (importPath == null || !_isRelativeImport(importPath)) {
            continue;
          }
          final resolved = p.posix.normalize(p.posix.join(dir, importPath));
          final owner = _lookupRegistryFileOwner(resolved);
          if (owner != null && owner.isShared) {
            deps.add(owner.id);
          }
        }
      } catch (_) {
        continue;
      }
    }

    _sharedDependencyCache[sharedId] = deps;
    return deps;
  }

  bool _isRelativeImport(String path) {
    return path.startsWith('.');
  }

  Map<String, _RegistryFileOwner> _buildRegistryFileIndex() {
    final cached = _registryFileIndex;
    if (cached != null) {
      return cached;
    }
    final index = <String, _RegistryFileOwner>{};
    for (final sharedItem in registry.shared) {
      for (final file in sharedItem.files) {
        final normalized = _normalizeRegistryPath(file.source);
        index[normalized] = _RegistryFileOwner.shared(sharedItem.id, file);
      }
    }
    for (final component in registry.components) {
      for (final file in component.files) {
        final normalized = _normalizeRegistryPath(file.source);
        index[normalized] = _RegistryFileOwner.component(component.id, file);
      }
    }
    _registryFileIndex = index;
    return index;
  }

  _RegistryFileOwner? _lookupRegistryFileOwner(String source) {
    final normalized = _normalizeRegistryPath(source);
    return _buildRegistryFileIndex()[normalized];
  }

  String _normalizeRegistryPath(String source) {
    final normalized = source.replaceAll('\\', '/');
    return p.posix.normalize(normalized);
  }
}
