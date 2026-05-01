part of 'installer.dart';

const Set<String> _coreInitDependencies = {'data_widget', 'gap'};

extension InstallerManifestPart on Installer {
  Future<void> _updateComponentManifest() async {
    await _ensureConfigLoaded();
    final installPath = _installPath(_cachedConfig);
    final manifestFile = File(
      _resolveProjectPath(p.join(installPath, 'components.json')),
    );
    final installed = await _installedComponentIds();
    if (installed.isEmpty) {
      if (await manifestFile.exists()) {
        await manifestFile.delete();
      }
      await _clearComponentManifests();
      return;
    }
    final requiredDeps = _collectRequiredDependencies(installed);
    final installedList = installed.toList()..sort();
    final componentMeta = <String, dynamic>{};
    for (final id in installedList) {
      final component = registry.getComponent(id);
      if (component == null) {
        continue;
      }
      componentMeta[id] = {
        'version': component.version,
        'tags': component.tags
      };
    }
    final payload = {
      'schemaVersion': 1,
      'installPath': installPath,
      'sharedPath': _sharedPath(_cachedConfig),
      'installed': installedList,
      'managedDependencies': requiredDeps.keys.toList()..sort(),
      'componentMeta': componentMeta,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    if (!await manifestFile.parent.exists()) {
      await manifestFile.parent.create(recursive: true);
    }
    await manifestFile
        .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  }

  Directory _componentManifestDirectory() {
    return Directory(_resolveProjectPath(p.join('.shadcn', 'components')));
  }

  File _componentManifestFile(String componentId) {
    return File(
      _resolveProjectPath(p.join('.shadcn', 'components', '$componentId.json')),
    );
  }

  Future<void> _writeComponentManifest(Component component) async {
    final dir = _componentManifestDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = _componentManifestFile(component.id);
    String? installedAt;
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        if (data is Map<String, dynamic>) {
          final value = data['installedAt']?.toString();
          if (value != null && value.isNotEmpty) {
            installedAt = value;
          }
        }
      } catch (_) {
        installedAt = null;
      }
    }
    final payload = {
      'schemaVersion': 1,
      'id': component.id,
      'name': component.name,
      'version': component.version,
      'tags': component.tags,
      'installedAt': installedAt ?? DateTime.now().toUtc().toIso8601String(),
      'shared': component.shared.toList()..sort(),
      'dependsOn': component.dependsOn.toList()..sort(),
      'files': component.files.map((f) => f.source).toList()..sort(),
      'registryRoot': registry.registryRoot.root,
    };
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  }

  Future<void> _removeComponentManifest(String componentId) async {
    final file = _componentManifestFile(componentId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _clearComponentManifests() async {
    final dir = _componentManifestDirectory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> _refreshComponentManifests() async {
    final installed = await _installedComponentIds();
    for (final id in installed) {
      final component = registry.getComponent(id);
      if (component != null) {
        await _writeComponentManifest(component);
      }
    }
  }

  Map<String, dynamic> _collectRequiredDependencies(Set<String> installed) {
    final required = <String, dynamic>{};
    for (final id in installed) {
      final component = registry.getComponent(id);
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

  Future<void> _syncDependenciesWithInstalled({
    Set<String>? installedOverride,
    Set<String>? managedOverride,
  }) async {
    final pubspecFile = File(_resolveProjectPath('pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      return;
    }
    final installed = installedOverride ?? await _installedComponentIds();
    final required = _collectRequiredDependencies(installed);

    final managedDeps = managedOverride ?? await _loadManagedDependencies();
    final registryDeps = _collectAllRegistryDependencies();
    final toRemove = (managedDeps.isEmpty ? registryDeps : managedDeps)
        .difference(required.keys.toSet());

    if (toRemove.isNotEmpty) {
      logger.info('Removing dependencies: ${toRemove.join(', ')}');
      final result = await Process.run(
        'dart',
        ['pub', 'remove', ...toRemove],
        workingDirectory: targetDir,
      );
      if (result.exitCode != 0) {
        logger
            .detail('Some dependencies could not be removed: ${result.stderr}');
      }
    }

    final lines = pubspecFile.readAsLinesSync();
    final toAdd = <String>[];
    for (final entry in required.entries) {
      final dep = entry.key;
      final version = entry.value;
      final alreadyExists = lines.any((l) => l.trim().startsWith('$dep:'));
      if (alreadyExists) {
        continue;
      }
      if (version is String && version.isNotEmpty) {
        final cleanVersion =
            version.startsWith('^') ? version.substring(1) : version;
        toAdd.add('$dep:$cleanVersion');
      } else {
        toAdd.add(dep);
      }
    }

    if (toAdd.isNotEmpty) {
      logger.info('Adding dependencies: ${toAdd.join(', ')}');
      final result = await Process.run(
        'dart',
        ['pub', 'add', ...toAdd],
        workingDirectory: targetDir,
      );
      if (result.exitCode != 0) {
        logger.warn('Some dependencies could not be added: ${result.stderr}');
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
    await _ensureConfigLoaded();
    final config = _cachedConfig ?? const ShadcnConfig();
    final namespace = stateNamespace ?? config.effectiveDefaultNamespace;
    final installed = await _installedComponentIds();
    final required = _collectRequiredDependencies(installed);
    final managed = <String>{...required.keys, ..._coreInitDependencies};
    final existingState = await ShadcnState.load(
      targetDir,
      defaultNamespace: namespace,
    );
    final mergedRegistries = Map<String, RegistryStateEntry>.from(
        existingState.registries ?? const {});
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
    await generateAliases();
    await _updateState();
    logger.success('Sync complete');
  }
}
