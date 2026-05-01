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
    final projectRoot = findProjectRootFrom(targetDir);
    var config = await ShadcnConfig.load(projectRoot);
    final refs =
        await _resolveAddRequests(requested, config, projectRoot: projectRoot);

    final grouped = <String, List<String>>{};
    for (final ref in refs) {
      grouped.putIfAbsent(ref.namespace, () => []).add(ref.componentId);
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
        for (final componentId in entry.value) {
          await installer.addComponent(componentId);
        }
      });
    }

    await ShadcnConfig.save(projectRoot, config);
  }

  Future<List<AddRequest>> _resolveAddRequests(
    List<String> requested,
    ShadcnConfig config, {
    required String projectRoot,
  }) async {
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
}
