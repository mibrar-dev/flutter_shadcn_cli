part of 'multi_registry_manager.dart';

extension MultiRegistryAddPart on MultiRegistryManager {
  Future<void> runAdd(
    List<String> requested, {
    Set<String>? includeFileKinds,
    Set<String>? excludeFileKinds,
  }) async {
    if (requested.isEmpty) {
      throw MultiRegistryException('No components provided');
    }
    final projectRoot = _projectRoot;
    var config = await _loadProjectConfig();
    final refs =
        await _resolveAddRequests(requested, config, projectRoot: projectRoot);

    final grouped = <String, List<AddRequest>>{};
    for (final ref in refs) {
      grouped.putIfAbsent(ref.namespace, () => []).add(ref);
    }

    for (final entry in grouped.entries) {
      final source = await _resolveSourceForNamespace(
        entry.key,
        config,
        allowDirectoryFallback: true,
      );
      if (source.directoryEntry != null) {
        config =
            await _upsertConfigFromDirectory(config, source.directoryEntry!);
      }
      final supportsSharedGroups = source.configEntry?.capabilitySharedGroups ??
          source.directoryEntry?.capabilities.sharedGroups ??
          true;
      final supportsComposites = source.configEntry?.capabilityComposites ??
          source.directoryEntry?.capabilities.composites ??
          true;
      final registry =
          await _loadRegistryForSource(source, projectRoot: projectRoot);
      final installer = Installer(
        registry: registry,
        targetDir: projectRoot,
        logger: logger,
        installPathOverride: source.installRoot,
        sharedPathOverride: source.sharedRoot,
        stateNamespace: source.namespace,
        registryNamespace: source.namespace,
        includeFileKindsOverride: includeFileKinds,
        excludeFileKindsOverride: excludeFileKinds,
        enableSharedGroups: supportsSharedGroups,
        enableComposites: supportsComposites,
      );
      await installer.runBulkInstall(() async {
        for (final request in entry.value) {
          _ensureRequestedVersion(registry, request);
          await installer.addComponent(request.componentId);
        }
      });
    }

    await _saveProjectConfig(config);
  }

  Future<List<AddRequest>> _resolveAddRequests(
    List<String> requested,
    ShadcnConfig config, {
    required String projectRoot,
  }) async {
    final batched = await _tryResolveAddRequestsFromRegistryIndex(
      requested,
      config,
      projectRoot: projectRoot,
    );
    if (batched != null) {
      return batched;
    }

    try {
      return await addResolutionService.resolveAddRequests(
        requested: requested,
        config: config,
        componentExists: (namespace, componentId) async {
          final source = await _resolveSourceForNamespace(
            namespace,
            config,
            allowDirectoryFallback: true,
          );
          final registry = await _loadRegistryForSource(
            source,
            projectRoot: projectRoot,
          );
          return registry.getComponent(componentId) != null;
        },
      );
    } catch (e) {
      if (e is RegistrySchemaValidationException) {
        rethrow;
      }
      throw MultiRegistryException(
          e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<List<AddRequest>?> _tryResolveAddRequestsFromRegistryIndex(
    List<String> requested,
    ShadcnConfig config, {
    required String projectRoot,
  }) async {
    final resolved = List<AddRequest?>.filled(requested.length, null);
    final unqualified = <String>[];
    final unqualifiedIndexes = <int>[];

    for (var i = 0; i < requested.length; i += 1) {
      final token = requested[i];
      final qualified = AddResolutionService.parseQualifiedComponentRef(token);
      if (qualified != null) {
        resolved[i] = AddRequest(
          namespace: qualified.namespace,
          componentId: qualified.componentId,
          version: qualified.version,
        );
        continue;
      }
      if (ComponentRefNormalizer.looksQualified(token)) {
        throw MultiRegistryException(
          'Invalid component address "$token". Use @namespace/component',
        );
      }
      unqualified.add(token);
      unqualifiedIndexes.add(i);
    }

    if (unqualified.isEmpty) {
      return resolved.whereType<AddRequest>().toList();
    }

    final enabledNamespaces = _enabledRegistryNamespaces(config);
    final availability = <String, List<String>>{};
    for (final namespace in enabledNamespaces) {
      final source = await _resolveSourceForNamespace(
        namespace,
        config,
        allowDirectoryFallback: true,
      );
      final registry = await _loadRegistryForSource(
        source,
        projectRoot: projectRoot,
      );
      for (final token in unqualified) {
        if (registry.getComponent(token) != null) {
          availability.putIfAbsent(token, () => <String>[]).add(namespace);
        }
      }
    }

    for (var i = 0; i < unqualified.length; i += 1) {
      final token = unqualified[i];
      final candidates = availability[token] ?? const <String>[];
      if (candidates.isEmpty) {
        throw MultiRegistryException('Component "$token" not found.');
      }
      if (candidates.length > 1) {
        final sorted = [...candidates]..sort();
        throw MultiRegistryException(
          'Component "$token" is ambiguous across registries (${sorted.join(', ')}). '
          'Use @namespace/component',
        );
      }
      resolved[unqualifiedIndexes[i]] = AddRequest(
        namespace: candidates.single,
        componentId: token,
      );
    }
    return resolved.whereType<AddRequest>().toList();
  }

  Set<String> _enabledRegistryNamespaces(ShadcnConfig config) {
    final enabled = (config.registries ?? const <String, RegistryConfigEntry>{})
        .entries
        .where((entry) => entry.value.enabled)
        .map((entry) => entry.key)
        .toSet();
    if (enabled.isEmpty) {
      enabled.add(config.effectiveDefaultNamespace);
    }
    return enabled;
  }

  void _ensureRequestedVersion(Registry registry, AddRequest request) {
    final requestedVersion = request.version;
    if (requestedVersion == null || requestedVersion.isEmpty) {
      return;
    }
    final component = registry.getComponent(request.componentId);
    if (component == null) {
      return;
    }
    if (component.version != requestedVersion) {
      throw MultiRegistryException(
        'Component ${request.componentId} in ${request.namespace} is '
        'version ${component.version ?? 'unknown'}, not $requestedVersion.',
      );
    }
  }
}
