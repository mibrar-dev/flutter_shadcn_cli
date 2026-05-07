part of 'installer.dart';

extension InstallerFileInstallPart on Installer {
  Future<void> _installFile(RegistryFile file) async {
    await _ensureConfigLoaded();
    final destFile = File(_resolveDestinationPath(file.destination));

    if (!await destFile.parent.exists()) {
      _recordDirectoryCreateTree(destFile.parent);
      await destFile.parent.create(recursive: true);
    }

    if (!_shouldInstallFile(file.destination)) {
      logger.detail('Skipping optional ${file.destination}');
      return;
    }

    logger.detail('Writing ${destFile.path}');
    final bytes = await registry.readSourceBytes(file.source);
    _recordFileWrite(destFile);
    await destFile.writeAsBytes(bytes, flush: true);
  }

  Future<void> _installComponentFile(
    Component component,
    RegistryFile file,
    List<RegistryFile> availableFiles,
  ) async {
    await _ensureConfigLoaded();
    await _installFileDependencies(component, file, availableFiles);
    final destination = _resolveComponentDestination(component, file);
    final patched = RegistryFile(
      source: file.source,
      destination: destination,
      dependsOn: file.dependsOn,
    );
    await _installFile(patched);
  }

  Future<void> _installComponentFiles(Component component) async {
    final files = component.files;
    if (files.isEmpty) {
      return;
    }
    var index = 0;
    Future<void> worker() async {
      while (true) {
        if (index >= files.length) {
          return;
        }
        final file = files[index++];
        await _installComponentFile(component, file, files);
      }
    }

    final workerCount = Installer._fileCopyConcurrency.clamp(1, files.length);
    await Future.wait(List.generate(workerCount, (_) => worker()));
  }

  Future<void> _installFileWithDependencies(
    RegistryFile file,
    List<RegistryFile> availableFiles, {
    String? sharedId,
  }) async {
    await _ensureConfigLoaded();
    await _installSharedFileDependencies(
      file,
      availableFiles,
      sharedId: sharedId,
    );
    await _installFile(file);
  }

  Future<void> _installFileDependencies(
    Component component,
    RegistryFile file,
    List<RegistryFile> availableFiles,
  ) async {
    if (file.dependsOn.isEmpty) {
      return;
    }
    for (final dep in file.dependsOn) {
      final normalizedSource = _normalizeRegistryPath(dep.source);
      final mapping = _findFileMapping(availableFiles, normalizedSource);
      final owner = _lookupRegistryFileOwner(normalizedSource);

      if (owner != null && owner.isShared) {
        await installShared(owner.id);
        continue;
      }

      if (owner != null && owner.isComponent && owner.id != component.id) {
        if (!dep.optional) {
          logger.warn(
              'File dependency ${dep.source} belongs to component ${owner.id}.');
        }
        continue;
      }

      final resolvedMapping = mapping ??
          owner?.file ??
          RegistryFile(source: dep.source, destination: dep.source);
      final destination =
          _resolveComponentDestination(component, resolvedMapping);
      final target = File(destination);
      if (await target.exists()) {
        continue;
      }
      if (!await _safeInstallDependency(
          component, resolvedMapping, availableFiles)) {
        if (!dep.optional) {
          logger.warn('Missing dependency file: ${dep.source}');
        }
      }
    }
  }

  Future<void> _installSharedFileDependencies(
    RegistryFile file,
    List<RegistryFile> availableFiles, {
    String? sharedId,
  }) async {
    if (file.dependsOn.isEmpty) {
      return;
    }
    for (final dep in file.dependsOn) {
      final normalizedSource = _normalizeRegistryPath(dep.source);
      final mapping = _findFileMapping(availableFiles, normalizedSource);
      final owner = _lookupRegistryFileOwner(normalizedSource);

      if (owner != null && owner.isShared && owner.id != sharedId) {
        await installShared(owner.id);
        continue;
      }

      if (owner != null && owner.isComponent) {
        if (!dep.optional) {
          logger.warn(
            'Shared file dependency ${dep.source} belongs to component ${owner.id}.',
          );
        }
        continue;
      }

      final resolvedMapping = mapping ??
          owner?.file ??
          RegistryFile(source: dep.source, destination: dep.source);
      final target = File(_resolveDestinationPath(resolvedMapping.destination));
      if (await target.exists()) {
        continue;
      }
      await _installFile(resolvedMapping);
    }
  }

  Future<bool> _safeInstallDependency(
    Component component,
    RegistryFile mapping,
    List<RegistryFile> availableFiles,
  ) async {
    try {
      await _installComponentFile(component, mapping, availableFiles);
      return true;
    } on ResolverV1Exception {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  RegistryFile? _findFileMapping(
    List<RegistryFile> availableFiles,
    String source,
  ) {
    final normalizedSource = _normalizeRegistryPath(source);
    for (final file in availableFiles) {
      if (_normalizeRegistryPath(file.source) == normalizedSource) {
        return file;
      }
    }
    return null;
  }

  String _resolveComponentDestination(Component component, RegistryFile file) {
    final config = _cachedConfig;
    final installPath = _installPath(config);
    final source = file.source.replaceAll('\\', '/');

    const registryPrefix = 'registry/';
    if (source.startsWith(registryPrefix)) {
      final relative = source.substring(registryPrefix.length);
      return _resolveProjectPath(p.join(installPath, relative));
    }

    return _resolveDestinationPath(file.destination);
  }
}
