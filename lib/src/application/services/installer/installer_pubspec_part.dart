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
    if (installPathOverride != null && installPathOverride!.isNotEmpty) {
      return _expandAliases(installPathOverride!, config?.pathAliases);
    }
    final registryEntry = registryNamespace == null
        ? null
        : config?.registryConfig(registryNamespace);
    final override = registryEntry?.installPath ?? config?.installPath;
    if (override != null && override.isNotEmpty) {
      return _expandAliases(override, config?.pathAliases);
    }
    return _defaultInstallPath;
  }

  String _sharedPath(ShadcnConfig? config) {
    if (sharedPathOverride != null && sharedPathOverride!.isNotEmpty) {
      return _expandAliases(sharedPathOverride!, config?.pathAliases);
    }
    final registryEntry = registryNamespace == null
        ? null
        : config?.registryConfig(registryNamespace);
    final override = registryEntry?.sharedPath ?? config?.sharedPath;
    if (override != null && override.isNotEmpty) {
      return _expandAliases(override, config?.pathAliases);
    }
    return _defaultSharedPath;
  }

  bool _shouldInstallFile(String destination) {
    final lower = destination.toLowerCase();
    final optionalKinds = _optionalFileKinds(lower);
    if (optionalKinds.isEmpty) {
      return true;
    }

    final includeOverride = includeFileKindsOverride ?? const <String>{};
    final excludeOverride = excludeFileKindsOverride ?? const <String>{};
    if (includeOverride.isNotEmpty) {
      return optionalKinds.any(includeOverride.contains);
    }
    if (excludeOverride.isNotEmpty &&
        optionalKinds.any(excludeOverride.contains)) {
      return false;
    }

    final config = _cachedConfig ?? const ShadcnConfig();
    final registryEntry = registryNamespace == null
        ? null
        : config.registryConfig(registryNamespace);

    final includeFromConfig = _normalizeFileKinds(
      registryEntry?.includeFiles ?? config.includeFiles ?? const <String>[],
    );
    if (includeFromConfig.isNotEmpty) {
      return optionalKinds.any(includeFromConfig.contains);
    }
    final excludeFromConfig = _normalizeFileKinds(
      registryEntry?.excludeFiles ?? config.excludeFiles ?? const <String>[],
    );
    if (excludeFromConfig.isNotEmpty &&
        optionalKinds.any(excludeFromConfig.contains)) {
      return false;
    }

    if (optionalKinds.contains('readme')) {
      return registryEntry?.includeReadme ?? config.includeReadme ?? false;
    }
    if (optionalKinds.contains('meta')) {
      return registryEntry?.includeMeta ?? config.includeMeta ?? true;
    }
    if (optionalKinds.contains('preview')) {
      return registryEntry?.includePreview ?? config.includePreview ?? false;
    }
    return true;
  }

  Set<String> _optionalFileKinds(String destinationLower) {
    final normalized = destinationLower.replaceAll('\\', '/');
    final base = p.posix.basename(normalized);
    final kinds = <String>{};
    if (base == 'readme.md' || base.contains('readme')) {
      kinds.add('readme');
    }
    if (base == 'meta.json' ||
        base.startsWith('meta.') ||
        base.contains('meta')) {
      kinds.add('meta');
    }
    if (base.contains('preview')) {
      kinds.add('preview');
    }
    return kinds;
  }

  Set<String> _normalizeFileKinds(Iterable<String> values) {
    final normalized = <String>{};
    for (final value in values) {
      final token = value.trim().toLowerCase();
      switch (token) {
        case 'readme':
        case 'docs':
          normalized.add('readme');
          break;
        case 'meta':
        case 'metadata':
          normalized.add('meta');
          break;
        case 'preview':
        case 'previews':
          normalized.add('preview');
          break;
      }
    }
    return normalized;
  }

  Future<void> _ensureConfigLoaded() async {
    _cachedConfig ??= await ShadcnConfig.load(targetDir);
  }

  String get _defaultInstallPath {
    return registry.defaults['installPath'] ?? 'lib/ui/shadcn';
  }

  String get _defaultSharedPath {
    return registry.defaults['sharedPath'] ?? 'lib/ui/shadcn/shared';
  }

  Future<void> _updateDependencies(Map<String, dynamic> deps) async {
    if (deps.isEmpty) {
      return;
    }

    final pubspecFile = File(_resolveProjectPath('pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      logger.warn('pubspec.yaml not found; skipping dependency updates.');
      return;
    }

    final content = pubspecFile.readAsStringSync();
    final editor = PubspecEditor(content);
    editor.addDependencies(deps);
    await pubspecFile.writeAsString(editor.toString());
  }

  Future<void> _updateAssets(List<String> assets) async {
    if (assets.isEmpty) {
      return;
    }
    final pubspecFile = File(_resolveProjectPath('pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      logger.warn('pubspec.yaml not found; skipping asset updates.');
      return;
    }

    final content = pubspecFile.readAsStringSync();
    final editor = PubspecEditor(content);
    editor.addFlutterAssets(assets);
    await pubspecFile.writeAsString(editor.toString());
  }

  Future<void> _updateFonts(List<FontEntry> fonts) async {
    if (fonts.isEmpty) {
      return;
    }
    final pubspecFile = File(_resolveProjectPath('pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      logger.warn('pubspec.yaml not found; skipping font updates.');
      return;
    }

    final content = pubspecFile.readAsStringSync();
    final editor = PubspecEditor(content);
    editor.addFlutterFonts(fonts
        .map((entry) => PubspecFontFamily(
              entry.family,
              entry.fonts
                  .map((font) => PubspecFontAsset(
                        font.asset,
                        weight: font.weight,
                        style: font.style,
                      ))
                  .toList(),
            ))
        .toList());
    await pubspecFile.writeAsString(editor.toString());
  }
}
