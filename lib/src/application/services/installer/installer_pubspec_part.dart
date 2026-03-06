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

    return p.join(targetDir, destPath);
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

    final pubspecFile = File(p.join(targetDir, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      logger.warn('pubspec.yaml not found; skipping dependency updates.');
      return;
    }

    final lines = pubspecFile.readAsLinesSync();
    final result = _applyDependencies(lines, deps);
    if (result.added.isEmpty) {
      logger.detail('Dependencies already present.');
      return;
    }

    await pubspecFile.writeAsString(result.lines.join('\n'));
    logger.success('Added dependencies: ${result.added.join(', ')}');
  }

  Future<void> _updateAssets(List<String> assets) async {
    if (assets.isEmpty) {
      return;
    }
    final pubspecFile = File(p.join(targetDir, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      logger.warn('pubspec.yaml not found; skipping asset updates.');
      return;
    }

    final lines = pubspecFile.readAsLinesSync();
    final result = _applyAssets(lines, assets);
    if (result.added.isEmpty) {
      logger.detail('Assets already present.');
      return;
    }

    await pubspecFile.writeAsString(result.lines.join('\n'));
    logger.success('Added assets: ${result.added.join(', ')}');
  }

  Future<void> _updateFonts(List<FontEntry> fonts) async {
    if (fonts.isEmpty) {
      return;
    }
    final pubspecFile = File(p.join(targetDir, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      logger.warn('pubspec.yaml not found; skipping font updates.');
      return;
    }

    final lines = pubspecFile.readAsLinesSync();
    final result = _applyFonts(lines, fonts);
    if (result.added.isEmpty) {
      logger.detail('Fonts already present.');
      return;
    }

    await pubspecFile.writeAsString(result.lines.join('\n'));
    logger.success('Added font families: ${result.added.join(', ')}');
  }

  _DependencyUpdateResult _applyDependencies(
    List<String> lines,
    Map<String, dynamic> deps,
  ) {
    final existing = _collectExistingDependencies(lines);
    final additions = <String, dynamic>{};
    deps.forEach((key, value) {
      if (!existing.contains(key)) {
        additions[key] = value;
      }
    });

    if (additions.isEmpty) {
      return _DependencyUpdateResult(lines, const []);
    }

    final update = _insertDependencies(lines, additions);
    return _DependencyUpdateResult(update, additions.keys.toList()..sort());
  }

  _AssetsUpdateResult _applyAssets(List<String> lines, List<String> assets) {
    final normalized = assets.where((a) => a.trim().isNotEmpty).toSet().toList()
      ..sort();
    if (normalized.isEmpty) {
      return _AssetsUpdateResult(lines, const []);
    }

    final flutterRange = _findFlutterSection(lines);
    if (flutterRange.start == -1) {
      final addedLines = <String>[
        'flutter:',
        '  assets:',
        ...normalized.map((a) => '    - $a')
      ];
      return _AssetsUpdateResult(
          [...lines, if (lines.isNotEmpty) '', ...addedLines], normalized);
    }

    final flutterIndent = _leadingSpaces(lines[flutterRange.start]);
    final assetsIndex = _findSectionLine(lines, flutterRange, 'assets:');
    if (assetsIndex == -1) {
      final insertIndex = flutterRange.end;
      final assetsIndent = ' ' * (flutterIndent + 2);
      final assetItemIndent = ' ' * (flutterIndent + 4);
      final insertion = <String>[
        '$assetsIndent' 'assets:',
        ...normalized.map((a) => '$assetItemIndent- $a'),
      ];
      final updated = [...lines]..insertAll(insertIndex, insertion);
      return _AssetsUpdateResult(updated, normalized);
    }

    final assetsIndentCount = _leadingSpaces(lines[assetsIndex]);
    final assetItemIndent = ' ' * (assetsIndentCount + 2);
    final existing = <String>{};
    var insertAt = assetsIndex + 1;
    for (var i = assetsIndex + 1; i < flutterRange.end; i++) {
      final line = lines[i];
      if (line.trim().isEmpty || line.trim().startsWith('#')) {
        continue;
      }
      if (_leadingSpaces(line) <= assetsIndentCount) {
        break;
      }
      if (line.trim().startsWith('- ')) {
        existing.add(line.trim().substring(2).trim());
        insertAt = i + 1;
      }
    }

    final additions = normalized.where((a) => !existing.contains(a)).toList();
    if (additions.isEmpty) {
      return _AssetsUpdateResult(lines, const []);
    }
    final updated = [...lines]
      ..insertAll(insertAt, additions.map((a) => '$assetItemIndent- $a'));
    return _AssetsUpdateResult(updated, additions);
  }

  _FontsUpdateResult _applyFonts(List<String> lines, List<FontEntry> fonts) {
    if (fonts.isEmpty) {
      return _FontsUpdateResult(lines, const []);
    }

    final flutterRange = _findFlutterSection(lines);
    if (flutterRange.start == -1) {
      final addedLines = <String>['flutter:', ..._formatFontSection(fonts, 2)];
      final addedFamilies = fonts.map((f) => f.family).toList()..sort();
      return _FontsUpdateResult(
          [...lines, if (lines.isNotEmpty) '', ...addedLines], addedFamilies);
    }

    final flutterIndent = _leadingSpaces(lines[flutterRange.start]);
    final fontsIndex = _findSectionLine(lines, flutterRange, 'fonts:');
    if (fontsIndex == -1) {
      final insertIndex = flutterRange.end;
      final insertion = _formatFontSection(fonts, flutterIndent + 2);
      final updated = [...lines]..insertAll(insertIndex, insertion);
      final addedFamilies = fonts.map((f) => f.family).toList()..sort();
      return _FontsUpdateResult(updated, addedFamilies);
    }

    final fontsIndentCount = _leadingSpaces(lines[fontsIndex]);
    final fontsRange = _findSectionEnd(lines, fontsIndex, fontsIndentCount);
    final existingFamilies = <String>{};
    for (var i = fontsIndex + 1; i < fontsRange.end; i++) {
      final line = lines[i].trimLeft();
      if (line.startsWith('- family:')) {
        final family = line.split(':').skip(1).join(':').trim();
        if (family.isNotEmpty) {
          existingFamilies.add(family);
        }
      }
    }

    final additions =
        fonts.where((f) => !existingFamilies.contains(f.family)).toList();
    if (additions.isEmpty) {
      return _FontsUpdateResult(lines, const []);
    }

    final insertion = _formatFontSection(additions, fontsIndentCount + 2);
    final updated = [...lines]..insertAll(fontsRange.end, insertion);
    final addedFamilies = additions.map((f) => f.family).toList()..sort();
    return _FontsUpdateResult(updated, addedFamilies);
  }

  Set<String> _collectExistingDependencies(List<String> lines) {
    final deps = <String>{};
    var inDeps = false;
    var depsIndent = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      if (trimmed == 'dependencies:') {
        inDeps = true;
        depsIndent = line.indexOf('dependencies:');
        continue;
      }
      if (inDeps) {
        final currentIndent = line.indexOf(trimmed);
        if (currentIndent <= depsIndent) {
          inDeps = false;
          continue;
        }
        final match = RegExp(r'^([A-Za-z0-9_\-]+):').firstMatch(trimmed);
        if (match != null) {
          deps.add(match.group(1)!);
        }
      }
    }

    if (!inDeps) {
      var inDev = false;
      var devIndent = 0;
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) {
          continue;
        }
        if (trimmed == 'dev_dependencies:') {
          inDev = true;
          devIndent = line.indexOf('dev_dependencies:');
          continue;
        }
        if (inDev) {
          final currentIndent = line.indexOf(trimmed);
          if (currentIndent <= devIndent) {
            inDev = false;
            continue;
          }
          final match = RegExp(r'^([A-Za-z0-9_\-]+):').firstMatch(trimmed);
          if (match != null) {
            deps.add(match.group(1)!);
          }
        }
      }
    }

    return deps;
  }

  List<String> _insertDependencies(
    List<String> lines,
    Map<String, dynamic> additions,
  ) {
    final updated = List<String>.from(lines);
    final depsIndex = _findSectionIndex(updated, 'dependencies:');
    if (depsIndex == -1) {
      updated.add('');
      updated.add('dependencies:');
      const indent = '  ';
      final entries = additions.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final entry in entries) {
        updated.addAll(_formatDependencyLines(entry.key, entry.value, indent));
      }
      return updated;
    }

    final depsIndent = _leadingSpaces(updated[depsIndex]);
    final childIndent = ' ' * (depsIndent + 2);
    var insertIndex = depsIndex + 1;
    while (insertIndex < updated.length) {
      final line = updated[insertIndex];
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        insertIndex++;
        continue;
      }
      final indent = _leadingSpaces(line);
      if (indent <= depsIndent) {
        break;
      }
      insertIndex++;
    }

    final entries = additions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final linesToInsert = <String>[];
    for (final entry in entries) {
      linesToInsert
          .addAll(_formatDependencyLines(entry.key, entry.value, childIndent));
    }
    updated.insertAll(insertIndex, linesToInsert);
    return updated;
  }

  List<String> _formatDependencyLines(
      String key, dynamic value, String indent) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('sdk:')) {
        final sdkValue = trimmed.split(':').skip(1).join(':').trim();
        return ['$indent$key:', '$indent  sdk: $sdkValue'];
      }
    }
    if (value is Map) {
      final lines = <String>['$indent$key:'];
      final childIndent = '$indent  ';
      value.forEach((k, v) {
        lines.add('$childIndent$k: $v');
      });
      return lines;
    }
    return ['$indent$key: ${value.toString()}'];
  }

  int _findSectionIndex(List<String> lines, String section) {
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim() == section) {
        return i;
      }
    }
    return -1;
  }

  _SectionRange _findFlutterSection(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim() == 'flutter:' && _leadingSpaces(lines[i]) == 0) {
        final end = _findSectionEnd(lines, i, 0).end;
        return _SectionRange(i, end);
      }
    }
    return const _SectionRange(-1, -1);
  }

  int _findSectionLine(List<String> lines, _SectionRange range, String key) {
    for (var i = range.start + 1; i < range.end; i++) {
      if (lines[i].trim() == key) {
        return i;
      }
    }
    return -1;
  }

  _SectionRange _findSectionEnd(List<String> lines, int start, int indent) {
    var end = lines.length;
    for (var i = start + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty || line.trim().startsWith('#')) {
        continue;
      }
      if (_leadingSpaces(line) <= indent) {
        end = i;
        break;
      }
    }
    return _SectionRange(start, end);
  }

  List<String> _formatFontSection(List<FontEntry> fonts, int indentCount) {
    final indent = ' ' * indentCount;
    final itemIndent = ' ' * (indentCount + 2);
    final innerIndent = ' ' * (indentCount + 4);
    final assetIndent = ' ' * (indentCount + 6);
    final lines = <String>['$indent' 'fonts:'];
    for (final entry in fonts) {
      lines.add('$itemIndent- family: ${entry.family}');
      lines.add('$innerIndent' 'fonts:');
      for (final font in entry.fonts) {
        lines.add('$assetIndent- asset: ${font.asset}');
        if (font.weight != null) {
          lines.add('$assetIndent  weight: ${font.weight}');
        }
        if (font.style != null) {
          lines.add('$assetIndent  style: ${font.style}');
        }
      }
    }
    return lines;
  }

  int _leadingSpaces(String line) {
    var count = 0;
    for (final char in line.split('')) {
      if (char == ' ') {
        count++;
      } else {
        break;
      }
    }
    return count;
  }
}
