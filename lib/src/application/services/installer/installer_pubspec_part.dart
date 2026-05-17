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
    if (deps.isEmpty) {
      return;
    }

    final pubspecFile = File(_resolveProjectPath('pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      logger.warn('pubspec.yaml not found; skipping dependency updates.');
      return;
    }

    final content = pubspecFile.readAsStringSync();
    final result = _applyDependencies(content.split('\n'), deps);
    if (result.conflicts.isNotEmpty) {
      throw Exception(_formatDependencyConflicts(result.conflicts));
    }
    if (result.added.isEmpty) {
      logger.detail('Dependencies already present.');
      return;
    }

    final editor = PubspecEditor(content);
    editor.addDependencies(deps);
    await pubspecFile.writeAsString(editor.toString());
    logger.success('Added dependencies: ${result.added.join(', ')}');
  }

  Future<void> _preflightDependencies(Map<String, dynamic> deps) async {
    if (deps.isEmpty) {
      return;
    }
    final pubspecFile = File(_resolveProjectPath('pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      return;
    }
    final lines = pubspecFile.readAsLinesSync();
    final result = _applyDependencies(lines, deps);
    if (result.conflicts.isNotEmpty) {
      throw Exception(_formatDependencyConflicts(result.conflicts));
    }
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
    final delta = editor.recordDelta();
    if (delta.flutterAssets.isEmpty) {
      logger.detail('Assets already present.');
      return;
    }

    await pubspecFile.writeAsString(editor.toString());
    logger.success('Added assets: ${delta.flutterAssets.join(', ')}');
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
    editor.addFlutterFonts(
      fonts
          .map(
            (entry) => PubspecFontFamily(
              entry.family,
              entry.fonts
                  .map(
                    (font) => PubspecFontAsset(
                      font.asset,
                      weight: font.weight,
                      style: font.style,
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
    );
    final delta = editor.recordDelta();
    if (delta.flutterFonts.isEmpty) {
      logger.detail('Fonts already present.');
      return;
    }

    await pubspecFile.writeAsString(editor.toString());
    logger.success('Added font families: ${delta.flutterFonts.join(', ')}');
  }

  InstallerDependencyUpdateResult _applyDependencies(
    List<String> lines,
    Map<String, dynamic> deps,
  ) {
    final plan = const PubspecChangePlanner().planAddDependencies(lines, deps);
    return InstallerDependencyUpdateResult(
      plan.lines,
      plan.added.keys.toList()..sort(),
      plan.conflicts,
    );
  }

  String _formatDependencyConflicts(
    List<PubspecDependencyConflict> conflicts,
  ) {
    final details = conflicts
        .map(
          (conflict) =>
              '${conflict.package} existing ${conflict.existing}, requested ${conflict.requested}',
        )
        .join('; ');
    return 'pubspec.yaml dependency conflict: $details. '
        'Keep the existing constraint, update it manually, or remove it before retrying.';
  }
}
