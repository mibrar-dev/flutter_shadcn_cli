part of 'installer.dart';

const Set<String> _coreInitDependencies = {'data_widget', 'gap'};

extension InstallerManifestPart on Installer {
  Future<void> _updateComponentManifest() async {
    logger.progress('Syncing component registry manifest');
    await _ensureConfigLoaded();
    final installPath = _installPath(_cachedConfig);
    final installed = await _installedComponentIds();
    final requiredDeps = await _collectRequiredDependencies(installed);
    final componentMeta = await _collectComponentMeta(installed);
    await _manifestService.updateAggregateManifest(
      installPath: installPath,
      sharedPath: _sharedPath(_cachedConfig),
      installedComponentIds: installed,
      managedDependencies: requiredDeps,
      componentMeta: componentMeta,
    );
  }

  Directory _componentManifestDirectory() {
    return _manifestService.componentManifestDirectory();
  }

  File _componentManifestFile(String componentId) {
    return _manifestService.componentManifestFile(componentId);
  }

  Future<void> _writeComponentManifest(
    Component component, {
    List<Map<String, dynamic>> localeResourcesInstalled = const [],
  }) async {
    await _manifestService.writeComponentManifest(
      component,
      localeResourcesInstalled: localeResourcesInstalled,
    );
  }

  Future<void> _writeLockfileRecord(
    Component component, {
    List<Map<String, dynamic>> localeResourcesInstalled = const [],
  }) async {
    await _withLockfileWriteLock(() async {
      await _ensureConfigLoaded();
      final namespace = _effectiveNamespace();
      final manifestHash = _registryManifestHash();
      final localeKeys = localeResourcesInstalled.isNotEmpty
          ? _localeLockKeys(localeResourcesInstalled)
          : _existingLocaleLockKeys(component.id);
      final repository = ShadcnLockRepository(targetDir);
      final existing = await repository.loadOrSynthesize();
      final lock = existing
          .upsertRegistry(
            ShadcnLockRegistry(
              namespace: namespace,
              registryRoot: registry.registryRoot.root,
              sourceRoot: registry.sourceRoot.root,
              sourceManifestHash: manifestHash,
            ),
          )
          .upsertComponent(
            _pendingLockfileRecord(
              component,
              namespace,
              manifestHash,
              localeKeys: localeKeys,
            ),
          );
      await repository.save(lock);
    });
  }

  Future<void> _preflightNamespaceCollisions(Component component) async {
    await _ensureConfigLoaded();
    final namespace = _effectiveNamespace();
    final repository = ShadcnLockRepository(targetDir);
    final lock = await repository.loadOrSynthesize();
    const NamespaceCollisionPolicy().checkPendingInstall(
      lock: lock,
      pending: _pendingLockfileRecord(
        component,
        namespace,
        _registryManifestHash(),
      ),
      defaultNamespace: namespace,
    );
  }

  Future<void> _removeLockfileRecord(String componentId) async {
    await _withLockfileWriteLock(() async {
      await _ensureConfigLoaded();
      final repository = ShadcnLockRepository(targetDir);
      final existing = await repository.loadOrSynthesize();
      await repository.save(
        existing.removeComponent(
          namespace: _effectiveNamespace(),
          componentId: componentId,
        ),
      );
    });
  }

  Future<void> _withLockfileWriteLock(Future<void> Function() action) {
    final next = _lockfileWriteQueue.then((_) => action());
    _lockfileWriteQueue = next.catchError((_) {});
    return next;
  }

  Future<ShadcnLockComponent?> _lockfileComponentRecord(
    String componentId,
  ) async {
    await _ensureConfigLoaded();
    final repository = ShadcnLockRepository(targetDir);
    final lock = await repository.loadOrSynthesize();
    return lock.componentFor(
      namespace: _effectiveNamespace(),
      componentId: componentId,
    );
  }

  Future<bool> _lockfilePathOwnedByOther({
    required String relativePath,
    required String componentId,
  }) async {
    final repository = ShadcnLockRepository(targetDir);
    final lock = await repository.loadOrSynthesize();
    for (final component in lock.components) {
      if (component.namespace == _effectiveNamespace() &&
          component.componentId == componentId) {
        continue;
      }
      if (component.installedFiles.contains(relativePath)) {
        return true;
      }
    }
    return false;
  }

  String _effectiveNamespace() {
    final config = _cachedConfig ?? const ShadcnConfig();
    return stateNamespace ??
        registryNamespace ??
        config.effectiveDefaultNamespace;
  }

  String _registryManifestHash() {
    return sha256.convert(utf8.encode(jsonEncode(registry.data))).toString();
  }

  ShadcnLockComponent _pendingLockfileRecord(
    Component component,
    String namespace,
    String manifestHash, {
    List<String> localeKeys = const [],
  }) {
    return ShadcnLockComponent(
      namespace: namespace,
      componentId: component.id,
      qualifiedId: '@$namespace/${component.id}',
      version: component.version,
      registryRoot: registry.registryRoot.root,
      sourceManifestHash: manifestHash,
      installedFiles: _installedLockFiles(component),
      dependencies: _componentDependencies(component),
      postInstall: component.postInstall,
      localeKeys: localeKeys,
      assetPaths: component.assets,
      manifestKeys: component.manifestKeys,
      postInstallNamespaces: component.postInstallNamespaces,
      localeNamespaces: component.localeNamespaces,
      sharedFiles: const [],
    );
  }

  List<String> _installedLockFiles(Component component) {
    final root = p.normalize(p.absolute(targetDir));
    final files = <String>[];
    for (final file in component.files) {
      if (!_shouldInstallFile(file.destination)) {
        continue;
      }
      final destination = p.normalize(
        _resolveComponentDestination(component, file),
      );
      if (destination != root && !p.isWithin(root, destination)) {
        continue;
      }
      files.add(p.relative(destination, from: root));
    }
    files.sort();
    return files;
  }

  Map<String, dynamic> _componentDependencies(Component component) {
    final raw = component.pubspec['dependencies'];
    if (raw is! Map) {
      return const {};
    }
    return Map<String, dynamic>.from(raw);
  }

  List<String> _localeLockKeys(List<Map<String, dynamic>> resources) {
    final keys = <String>{};
    for (final resource in resources) {
      final destination = resource['destination']?.toString();
      final addedKeys = resource['addedKeys'];
      if (destination == null || destination.isEmpty || addedKeys is! List) {
        continue;
      }
      for (final key in addedKeys) {
        keys.add('$destination:${key.toString()}');
      }
    }
    return keys.toList()..sort();
  }

  List<String> _existingLocaleLockKeys(String componentId) {
    final manifestFile = _componentManifestFile(componentId);
    if (!manifestFile.existsSync()) {
      return const [];
    }
    try {
      final decoded = jsonDecode(manifestFile.readAsStringSync());
      if (decoded is! Map) {
        return const [];
      }
      final locale = decoded['locale'];
      final resources = locale is Map ? locale['resourcesInstalled'] : null;
      if (resources is! List) {
        return const [];
      }
      return _localeLockKeys(
        resources
            .whereType<Map>()
            .map(
              (entry) => entry.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
            .toList(),
      );
    } catch (_) {
      return const [];
    }
  }

  Future<void> _removeComponentManifest(String componentId) async {
    await _manifestService.removeComponentManifest(componentId);
  }

  Future<void> _refreshComponentManifests() async {
    final installed = await _installedComponentIds();
    for (final id in installed) {
      final component = await _manifestResolver.resolve(id);
      if (component != null) {
        await _writeComponentManifest(component);
      }
    }
  }

  Future<void> _refreshLockfileRecords() async {
    final installed = await _installedComponentIds();
    for (final id in installed) {
      final component = await _manifestResolver.resolve(id);
      if (component != null) {
        await _writeLockfileRecord(component);
      }
    }
  }

  Future<Map<String, dynamic>> _collectRequiredDependencies(
      Set<String> installed) async {
    final required = <String, dynamic>{};
    for (final id in installed) {
      final component = await _manifestResolver.resolve(id);
      if (component == null || component.pubspec.isEmpty) {
        continue;
      }
      final deps = component.pubspec['dependencies'] as Map<String, dynamic>?;
      if (deps == null) {
        continue;
      }
      deps.forEach((key, value) {
        required.putIfAbsent(key, () => value);
      });
    }
    return required;
  }

  Future<Map<String, dynamic>> _collectComponentMeta(
    Set<String> installed,
  ) async {
    final meta = <String, dynamic>{};
    final installedList = installed.toList()..sort();
    for (final id in installedList) {
      final component = await _manifestResolver.resolve(id);
      if (component == null) {
        continue;
      }
      meta[id] = {
        'version': component.version,
        'tags': component.tags,
      };
    }
    return meta;
  }

  Future<void> _syncDependenciesWithInstalled({
    Set<String>? installedOverride,
    Set<String>? managedOverride,
  }) async {
    final pubspecFile = File(_resolveProjectPath('pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      return;
    }
    final installed = installedOverride ?? await _installedComponentIds();
    final required = await _collectRequiredDependencies(installed);
    final lock = await ShadcnLockRepository(targetDir).loadOrSynthesize();
    for (final component in lock.components) {
      component.dependencies.forEach((key, value) {
        required.putIfAbsent(key, () => value);
      });
    }

    final managedDeps = managedOverride ?? await _loadManagedDependencies();
    final registryDeps = _collectAllRegistryDependencies();
    final toRemove = (managedDeps.isEmpty ? registryDeps : managedDeps)
        .difference(required.keys.toSet());

    final planner = const PubspecChangePlanner();
    var lines = pubspecFile.readAsLinesSync();
    final removePlan = planner.planRemoveDependencies(lines, toRemove);
    lines = removePlan.lines;

    final addPlan = planner.planAddDependencies(lines, required);
    if (addPlan.conflicts.isNotEmpty) {
      throw Exception(_formatDependencyConflicts(addPlan.conflicts));
    }
    lines = addPlan.lines;

    if (removePlan.removed.isNotEmpty || addPlan.added.isNotEmpty) {
      await pubspecFile.writeAsString(lines.join('\n'));
      if (removePlan.removed.isNotEmpty) {
        logger.info('Removed dependencies: ${removePlan.removed.join(', ')}');
      }
      if (addPlan.added.isNotEmpty) {
        logger.info('Added dependencies: ${addPlan.added.keys.join(', ')}');
      }
    }
  }

  Future<Set<String>> _loadManagedDependencies() async {
    final state = await ShadcnState.load(targetDir);
    return state.managedDependencies?.toSet() ?? {};
  }

  Set<String> _collectAllRegistryDependencies() {
    final deps = <String>{};
    for (final component in registry.components) {
      if (component.pubspec.isEmpty) {
        continue;
      }
      final map = component.pubspec['dependencies'] as Map<String, dynamic>?;
      if (map != null) {
        deps.addAll(map.keys);
      }
    }
    deps.addAll(_coreInitDependencies);
    return deps;
  }

  Future<void> _updateState() async {
    logger.progress('Updating project state');
    await _ensureConfigLoaded();
    final config = _cachedConfig ?? const ShadcnConfig();
    final namespace = stateNamespace ?? config.effectiveDefaultNamespace;
    final installed = await _installedComponentIds();
    final required = await _collectRequiredDependencies(installed);
    final managed = <String>{...required.keys, ..._coreInitDependencies};
    final existingState = await ShadcnState.load(
      targetDir,
      defaultNamespace: namespace,
    );
    final mergedRegistries = Map<String, RegistryStateEntry>.from(
      existingState.registries ?? const {},
    );
    mergedRegistries[namespace] = RegistryStateEntry(
      installPath: _installPath(config),
      sharedPath: _sharedPath(config),
      themeId: config.themeId,
    );
    await ShadcnState.save(
      targetDir,
      ShadcnState(
        installPath: _installPath(config),
        sharedPath: _sharedPath(config),
        themeId: config.themeId,
        managedDependencies: managed.toList()..sort(),
        registries: mergedRegistries,
      ),
    );
  }

  Future<void> syncFromConfig() async {
    await ensureInitFiles(allowPrompts: false);
    await _ensureConfigLoaded();
    final config = _cachedConfig ?? const ShadcnConfig();
    final state = await ShadcnState.load(targetDir);

    final newInstall = _installPath(config);
    final newShared = _sharedPath(config);

    if (state.installPath != null && state.installPath != newInstall) {
      final oldDir = Directory(_resolveProjectPath(state.installPath!));
      final newDir = Directory(_resolveProjectPath(newInstall));
      if (oldDir.existsSync()) {
        if (!newDir.parent.existsSync()) {
          newDir.parent.createSync(recursive: true);
        }
        oldDir.renameSync(newDir.path);
      }
    }

    if (state.sharedPath != null && state.sharedPath != newShared) {
      final oldShared = Directory(_resolveProjectPath(state.sharedPath!));
      final newSharedDir = Directory(_resolveProjectPath(newShared));
      if (oldShared.existsSync()) {
        if (!newSharedDir.parent.existsSync()) {
          newSharedDir.parent.createSync(recursive: true);
        }
        oldShared.renameSync(newSharedDir.path);
      }
    }

    if (config.themeId != null && config.themeId != state.themeId) {
      await applyThemeById(config.themeId!);
    }

    await _updateComponentManifest();
    await _refreshComponentManifests();
    await _refreshLockfileRecords();
    await generateAliases();
    await _updateState();
    logger.success('Sync complete');
  }
}
