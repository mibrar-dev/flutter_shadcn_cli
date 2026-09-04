part of 'installer.dart';

extension InstallerPubspecPart on Installer {
  String _resolveDestinationPath(String destination) {
    final config = _cachedConfig;
    final variables = {
      'installPath': _installPath(config),
      'sharedPath': _sharedPath(config),
    };

    String destPath = destination;
    variables.forEach((key, value) {
      destPath = destPath.replaceAll('{$key}', value);
    });

    return _resolveProjectOrAbsolutePath(destPath);
  }

  String _resolveProjectPath(String relativePath) {
    return ProjectPathGuard.resolveSafeWritePath(
      projectRoot: targetDir,
      destinationRelativePath: relativePath,
    );
  }

  String _resolveProjectOrAbsolutePath(String path) {
    if (!p.isAbsolute(path)) {
      return _resolveProjectPath(path);
    }
    final rootAbs = p.normalize(p.absolute(targetDir));
    final normalized = p.normalize(path);
    if (normalized != rootAbs && !p.isWithin(rootAbs, normalized)) {
      return ProjectPathGuard.resolveSafeWritePath(
        projectRoot: targetDir,
        destinationRelativePath: path,
      );
    }
    return _resolveProjectPath(p.relative(normalized, from: rootAbs));
  }

  String _installPath(ShadcnConfig? config) {
    return _configResolver.installPath(config);
  }

  String _sharedPath(ShadcnConfig? config) {
    return _configResolver.sharedPath(config);
  }

  bool _shouldInstallFile(String destination) {
    return _fileSelectionPolicy.shouldInstallFile(destination, _cachedConfig);
  }

  Future<void> _ensureConfigLoaded() async {
    _cachedConfig ??= await ShadcnConfig.load(targetDir);
  }

  String get _defaultInstallPath {
    return _configResolver.defaultInstallPath;
  }

  String get _defaultSharedPath {
    return _configResolver.defaultSharedPath;
  }

  Future<void> _updateDependencies(Map<String, dynamic> deps) async {
    await _pubspecService.updateDependencies(deps);
  }

  Future<void> _preflightDependencies(Map<String, dynamic> deps) async {
    await _pubspecService.preflightDependencies(deps);
  }

  Future<void> _updateAssets(List<String> assets) async {
    await _pubspecService.updateAssets(assets);
  }

  Future<void> _updateFonts(List<FontEntry> fonts) async {
    await _pubspecService.updateFonts(fonts);
  }

  String _formatDependencyConflicts(
    List<PubspecDependencyConflict> conflicts,
  ) {
    return _pubspecService.formatDependencyConflicts(conflicts);
  }
}
