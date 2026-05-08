part of 'installer.dart';

extension InstallerFileInstallPart on Installer {
  Future<String?> _installFile(RegistryFile file) async {
    await _ensureConfigLoaded();
    final destFile = File(_resolveDestinationPath(file.destination));
    final destinationRel = _relativeProjectPath(destFile.path);
    _rejectUnsupportedAssetStrategy(file, destinationRel);

    if (!await destFile.parent.exists()) {
      await destFile.parent.create(recursive: true);
    }

    if (!_shouldInstallFile(file.destination)) {
      logger.detail('Skipping optional ${file.destination}');
      return null;
    }

    if (await destFile.exists() && _isUserVisibleAssetPath(destinationRel)) {
      logger.warn('Preserved existing asset $destinationRel');
      return null;
    }

    logger.detail('Writing ${destFile.path}');
    final bytes = await registry.readSourceBytes(file.source);
    await destFile.writeAsBytes(bytes, flush: true);
    return destinationRel;
  }

  Future<String?> _installComponentFile(
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
      strategy: file.strategy,
    );
    return _installFile(patched);
  }

  Future<Set<String>> _installComponentFiles(Component component) async {
    final files = component.files;
    if (files.isEmpty) {
      return const <String>{};
    }
    var index = 0;
    final installed = <String>{};
    Future<void> worker() async {
      while (true) {
        if (index >= files.length) {
          return;
        }
        final file = files[index++];
        final written = await _installComponentFile(component, file, files);
        if (written != null) {
          installed.add(written);
        }
      }
    }

    final workerCount = Installer._fileCopyConcurrency.clamp(1, files.length);
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return installed;
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
    final explicitDestination = _resolveDestinationPath(file.destination);
    final explicitDestinationRel = _relativeProjectPath(explicitDestination);
    if (_isUserVisibleAssetPath(explicitDestinationRel)) {
      return explicitDestination;
    }

    const registryPrefix = 'registry/';
    if (source.startsWith(registryPrefix)) {
      final relative = source.substring(registryPrefix.length);
      return _resolveProjectPath(p.join(installPath, relative));
    }

    return explicitDestination;
  }

  String _relativeProjectPath(String absolutePath) {
    final root = p.normalize(p.absolute(targetDir));
    final normalized = p.normalize(absolutePath);
    return p.relative(normalized, from: root).replaceAll('\\', '/');
  }

  List<String> _copiedFlutterAssets(Set<String> installedFiles) {
    final assets = installedFiles.where(_isDerivableFlutterAssetPath).toList()
      ..sort();
    return assets;
  }

  void _rejectUnsupportedAssetStrategy(
    RegistryFile file,
    String destinationRel,
  ) {
    final strategy = file.strategy?.trim().toLowerCase();
    if (strategy == null || strategy.isEmpty) {
      return;
    }
    if (!_isBinaryAssetPath(destinationRel)) {
      return;
    }
    if (strategy == 'merge' || strategy.startsWith('merge_')) {
      throw Exception(
        'merge strategies are not supported for binary asset $destinationRel',
      );
    }
  }

  bool _isDerivableFlutterAssetPath(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    if (normalized.startsWith('lib/')) {
      return false;
    }
    if (normalized.endsWith('/')) {
      return false;
    }
    final extension = p.extension(normalized).toLowerCase();
    const assetExtensions = {
      '.jpg',
      '.json',
      '.otf',
      '.png',
      '.svg',
      '.ttf',
      '.webp',
      '.woff',
      '.woff2',
    };
    return assetExtensions.contains(extension);
  }

  bool _isBinaryAssetPath(String relativePath) {
    final extension = p.extension(relativePath).toLowerCase();
    const binaryAssetExtensions = {
      '.jpg',
      '.otf',
      '.png',
      '.svg',
      '.ttf',
      '.webp',
      '.woff',
      '.woff2',
    };
    return binaryAssetExtensions.contains(extension);
  }

  bool _isUserVisibleAssetPath(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    return normalized.startsWith('assets/') && _isBinaryAssetPath(normalized);
  }
}
