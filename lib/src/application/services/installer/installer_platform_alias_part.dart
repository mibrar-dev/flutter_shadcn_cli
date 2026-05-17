part of 'installer.dart';

extension InstallerPlatformAliasPart on Installer {
  Map<String, Map<String, String>> _platformTargets(ShadcnConfig? config) {
    final defaults = <String, Map<String, String>>{
      'android': {
        'permissions': 'android/app/src/main/AndroidManifest.xml',
        'gradle': 'android/app/build.gradle',
        'notes': '.shadcn/platform/android.md',
      },
      'ios': {
        'infoPlist': 'ios/Runner/Info.plist',
        'podfile': 'ios/Podfile',
        'notes': '.shadcn/platform/ios.md',
      },
      'macos': {
        'entitlements': 'macos/Runner/DebugProfile.entitlements',
        'notes': '.shadcn/platform/macos.md',
      },
      'desktop': {'config': '.shadcn/platform/desktop.md'},
    };
    final overrides = config?.platformTargets ?? const {};
    final merged = <String, Map<String, String>>{};
    for (final entry in defaults.entries) {
      merged[entry.key] = Map<String, String>.from(entry.value);
    }
    overrides.forEach((platform, value) {
      merged.putIfAbsent(platform, () => {});
      merged[platform]!.addAll(value);
    });
    return merged;
  }

  Future<void> _applyPlatformInstructions(Component component) async {
    if (component.platform.isEmpty) {
      return;
    }
    await _ensureConfigLoaded();
    final targets = _platformTargets(_cachedConfig);
    for (final entry in component.platform.entries) {
      final platform = entry.key;
      final instructions = entry.value;
      final platformTargets = targets[platform] ?? const {};

      await _writePlatformSection(
        platform: platform,
        section: 'permissions',
        targetPath: platformTargets['permissions'],
        lines: instructions.permissions,
      );
      await _writePlatformSection(
        platform: platform,
        section: 'gradle',
        targetPath: platformTargets['gradle'],
        lines: instructions.gradle,
      );
      await _writePlatformSection(
        platform: platform,
        section: 'podfile',
        targetPath: platformTargets['podfile'],
        lines: instructions.podfile,
      );
      await _writePlatformSection(
        platform: platform,
        section: 'entitlements',
        targetPath: platformTargets['entitlements'],
        lines: instructions.entitlements,
      );
      await _writePlatformSection(
        platform: platform,
        section: 'config',
        targetPath: platformTargets['config'],
        lines: instructions.config,
      );
      await _writePlatformSection(
        platform: platform,
        section: 'notes',
        targetPath: platformTargets['notes'],
        lines: instructions.notes,
      );

      if (instructions.infoPlist.isNotEmpty) {
        final plistLines = instructions.infoPlist.entries
            .map((e) => '${e.key}: ${e.value}')
            .toList();
        await _writePlatformSection(
          platform: platform,
          section: 'infoPlist',
          targetPath: platformTargets['infoPlist'],
          lines: plistLines,
        );
      }
    }
  }

  Future<void> _writePlatformSection({
    required String platform,
    required String section,
    required String? targetPath,
    required List<String> lines,
  }) async {
    if (lines.isEmpty) {
      return;
    }
    if (targetPath == null || targetPath.isEmpty) {
      logger.detail('No target configured for $platform/$section.');
      return;
    }
    final fullPath = _resolveProjectPath(targetPath);
    final file = File(fullPath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final marker = 'shadcn_flutter_cli:$platform:$section';
    final existing = await file.exists() ? await file.readAsString() : '';
    if (existing.contains(marker)) {
      return;
    }
    final block = _formatPlatformBlock(fullPath, marker, lines);
    await file.writeAsString(existing + block);
    logger.detail('Updated $targetPath ($platform/$section)');
  }

  String _formatPlatformBlock(String path, String marker, List<String> lines) {
    final ext = p.extension(path).toLowerCase();
    final isXml = ext == '.xml' || ext == '.plist' || ext == '.entitlements';
    final isMd = ext == '.md';
    if (isXml) {
      final buffer = StringBuffer();
      buffer.writeln('\n<!-- $marker:start -->');
      for (final line in lines) {
        buffer.writeln('<!-- $line -->');
      }
      buffer.writeln('<!-- $marker:end -->\n');
      return buffer.toString();
    }
    if (isMd) {
      final buffer = StringBuffer();
      buffer.writeln('\n## $marker');
      for (final line in lines) {
        buffer.writeln('- $line');
      }
      buffer.writeln('');
      return buffer.toString();
    }
    final buffer = StringBuffer();
    buffer.writeln('\n// $marker:start');
    for (final line in lines) {
      buffer.writeln('// $line');
    }
    buffer.writeln('// $marker:end\n');
    return buffer.toString();
  }

  void _reportPostInstall(Component component) {
    logger.section('Post-install notes for ${component.name}');
    for (final line in component.postInstall) {
      logger.info('  • $line');
    }
  }

  Future<void> generateAliases() async {
    await _ensureConfigLoaded();
    final config = _cachedConfig ?? const ShadcnConfig();
    final prefix = config.classPrefix;
    if (prefix == null || prefix.isEmpty) {
      return;
    }
    final componentsDir = Directory(
      _resolveProjectPath(p.join(_installPath(config), 'components')),
    );
    if (!componentsDir.existsSync()) {
      return;
    }

    final aliases = <String, InstallerAliasEntry>{};
    final imports = <String>{};
    final componentDirs = <String>{};
    for (final entity in componentsDir.listSync(recursive: true)) {
      if (entity is! Directory) {
        continue;
      }
      final name = p.basename(entity.path);
      final mainFile = File(p.join(entity.path, '$name.dart'));
      if (mainFile.existsSync()) {
        componentDirs.add(entity.path);
      }
    }

    for (final dirPath in componentDirs) {
      final componentDir = Directory(dirPath);
      final componentName = p.basename(componentDir.path);
      final mainFile = File(p.join(componentDir.path, '$componentName.dart'));
      if (!mainFile.existsSync()) {
        continue;
      }
      final relativeDir = p.relative(
        componentDir.path,
        from: p.join(targetDir, _installPath(config)),
      );
      final importPath =
          p.join(relativeDir, '$componentName.dart').replaceAll('\\', '/');
      imports.add(importPath);
      final contents = <String>[];
      final mainContent = mainFile.readAsStringSync();
      contents.add(mainContent);
      for (final part in _partRegex.allMatches(mainContent)) {
        final partPath = part.group(1);
        if (partPath == null) {
          continue;
        }
        final partFile = File(p.join(componentDir.path, partPath));
        if (partFile.existsSync()) {
          contents.add(partFile.readAsStringSync());
        }
      }
      final matches = contents.expand(
        (content) => _classRegex.allMatches(content),
      );
      for (final match in matches) {
        final className = match.group(2);
        if (className == null || className.startsWith('_')) {
          continue;
        }
        final typeParams = match.group(3);
        final aliasName = '$prefix$className';
        aliases.putIfAbsent(
            aliasName, () => InstallerAliasEntry(className, typeParams));
      }
    }

    final output = StringBuffer()
      ..writeln('// Generated by flutter_shadcn. Do not edit by hand.')
      ..writeln('library app_components;')
      ..writeln('');
    final hiddenMaterialNames = _materialNamesToHide(
      aliases.values.map((entry) => entry.className),
    );
    if (hiddenMaterialNames.isNotEmpty) {
      output.writeln("export 'package:flutter/material.dart' hide");
      for (var i = 0; i < hiddenMaterialNames.length; i += 1) {
        final suffix = i == hiddenMaterialNames.length - 1 ? ';' : ',';
        output.writeln('    ${hiddenMaterialNames[i]}$suffix');
      }
      output.writeln('');
    }
    final sortedImports = imports.toList()..sort();
    for (final importPath in sortedImports) {
      output.writeln("export '$importPath';");
    }
    output.writeln('');
    for (final importPath in sortedImports) {
      output.writeln("import '$importPath';");
    }
    output.writeln('');
    final aliasEntries = aliases.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in aliasEntries) {
      final aliasName = entry.key;
      final className = entry.value.className;
      final typeParams = entry.value.typeParams;
      if (typeParams == null || typeParams.isEmpty) {
        output.writeln('typedef $aliasName = $className;');
      } else {
        final typeArgs = _typeArgsFromParams(typeParams);
        output.writeln('typedef $aliasName$typeParams = $className$typeArgs;');
      }
    }

    final outputFile = File(
      _resolveProjectPath(p.join(_installPath(config), 'app_components.dart')),
    );
    await outputFile.writeAsString(output.toString());
  }

  List<String> _materialNamesToHide(Iterable<String> installedNames) {
    const materialExports = <String>{
      'AboutDialog',
      'ActionChip',
      'AlertDialog',
      'AppBar',
      'BackButton',
      'Badge',
      'BottomNavigationBar',
      'ButtonBar',
      'ButtonStyle',
      'ButtonTheme',
      'Card',
      'CardTheme',
      'Checkbox',
      'Chip',
      'CircularProgressIndicator',
      'Dialog',
      'DialogRoute',
      'Divider',
      'DividerTheme',
      'Drawer',
      'DrawerTheme',
      'DropdownButton',
      'ElevatedButton',
      'ElevatedButtonTheme',
      'FloatingActionButton',
      'Icon',
      'IconButton',
      'IconButtonTheme',
      'LinearProgressIndicator',
      'ListTile',
      'MenuBar',
      'MenuButtonTheme',
      'NavigationBar',
      'OutlinedButton',
      'OutlinedButtonTheme',
      'PopupMenuButton',
      'ProgressIndicator',
      'Radio',
      'Scaffold',
      'ScaffoldState',
      'SelectableText',
      'Slider',
      'Step',
      'StepState',
      'Stepper',
      'StepperType',
      'Switch',
      'Tab',
      'TabBar',
      'Table',
      'Text',
      'TextButton',
      'TextButtonTheme',
      'TextField',
      'Tooltip',
      'VerticalDivider',
      'showDialog',
    };
    final installedSet = installedNames.toSet();
    return materialExports.where((name) => installedSet.contains(name)).toList()
      ..sort();
  }
}
