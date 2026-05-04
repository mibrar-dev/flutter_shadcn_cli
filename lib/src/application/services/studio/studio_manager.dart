import 'dart:convert';
import 'dart:io';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_shadcn_cli/src/exit_codes.dart';

/// Manages the shadcn_flutter Studio lifecycle:
/// - install: scaffolds studio app and registry package
/// - sync: regenerates preview registry from installed components
/// - launch: runs the studio app
/// - doctor: diagnoses installation and sync state
class StudioManager {
  final String projectRoot;
  final String? registryRoot;

  StudioManager({
    required this.projectRoot,
    this.registryRoot,
  });

  /// Install the studio app for the first time
  Future<void> install() async {
    print('Installing shadcn_flutter Studio...');

    final studioDir = Directory(p.join(projectRoot, '.shadcn', 'studio'));
    if (studioDir.existsSync()) {
      print('Studio already exists at: ${studioDir.path}');
      print('To reinstall, delete the directory first.');
      return;
    }

    // 1. Read app package name from pubspec.yaml
    final appPackageName = await _getAppPackageName();
    print('  Detected app package: $appPackageName');

    // 2. Create studio directory structure
    studioDir.createSync(recursive: true);

    // 3. Copy studio template files
    await _copyStudioTemplate(studioDir, appPackageName);

    // 4. Create .studio_version marker
    final versionFile = File(p.join(studioDir.path, '.studio_version'));
    await versionFile.writeAsString('1.0.0');

    // 5. Run flutter pub get in studio
    print('  Running flutter pub get in studio...');
    final pubGetResult = await Process.run(
      'flutter',
      ['pub', 'get'],
      workingDirectory: studioDir.path,
    );
    if (pubGetResult.exitCode != 0) {
      print('  Warning: flutter pub get failed:');
      print(pubGetResult.stderr);
    }

    print('✓ Studio installed successfully at: ${studioDir.path}');
    print('');
    print('Next steps:');
    print('  1. Run: flutter_shadcn studio --sync');
    print('  2. Run: flutter_shadcn studio');
  }

  /// Sync studio registry with installed components
  Future<void> sync() async {
    print('Syncing studio with installed components...');

    final studioDir = Directory(p.join(projectRoot, '.shadcn', 'studio'));
    if (!studioDir.existsSync()) {
      print(
          'Error: Studio not installed. Run: flutter_shadcn studio --install');
      exit(ExitCodes.configInvalid);
    }

    // 1. Ensure tokens.json exists
    await _ensureTokensFile();

    // 2. Read installed components from config.json
    final installedComponents = await _getInstalledComponents();
    print('  Found ${installedComponents.length} installed components');

    // 3. Generate/update studio_registry package
    await _generateStudioRegistry(installedComponents);

    // 4. Update .last_sync timestamp
    final lastSyncFile = File(p.join(studioDir.path, '.last_sync'));
    await lastSyncFile.writeAsString(DateTime.now().toIso8601String());

    print('✓ Studio synced successfully');
    print('  Components registered: ${installedComponents.length}');
  }

  /// Launch the studio app
  Future<void> launch() async {
    print('Launching shadcn_flutter Studio...');

    final studioDir = Directory(p.join(projectRoot, '.shadcn', 'studio'));
    if (!studioDir.existsSync()) {
      print(
          'Error: Studio not installed. Run: flutter_shadcn studio --install');
      exit(ExitCodes.configInvalid);
    }

    // Check if sync is needed
    final needsSync = await _checkNeedsSync();
    if (needsSync) {
      print('Studio is out of sync with installed components.');
      print('Running sync...');
      await sync();
    }

    // Launch flutter run
    print('Starting studio on Chrome...');
    final runResult = await Process.start(
      'flutter',
      ['run', '-d', 'chrome'],
      workingDirectory: studioDir.path,
      mode: ProcessStartMode.inheritStdio,
    );

    await runResult.exitCode;
  }

  /// Check studio installation and sync status
  Future<void> doctor() async {
    print('shadcn_flutter Studio Doctor');
    print('═' * 50);

    final checks = <String, bool>{};

    // Check 1: Flutter available
    final flutterCheck = await _checkFlutter();
    checks['Flutter available'] = flutterCheck;
    _printCheck('Flutter available', flutterCheck);

    // Check 2: Studio installed
    final studioDir = Directory(p.join(projectRoot, '.shadcn', 'studio'));
    final studioExists = studioDir.existsSync();
    checks['Studio installed'] = studioExists;
    _printCheck('Studio installed', studioExists,
        path: studioExists ? studioDir.path : null);

    if (!studioExists) {
      print('');
      print('Fix: Run: flutter_shadcn studio --install');
      return;
    }

    // Check 3: Studio registry exists
    final registryDir =
        Directory(p.join(projectRoot, '.shadcn', 'studio_registry'));
    final registryExists = registryDir.existsSync();
    checks['Studio registry package'] = registryExists;
    _printCheck('Studio registry package', registryExists,
        path: registryExists ? registryDir.path : null);

    // Check 4: tokens.json exists and valid
    final tokensFile = File(p.join(projectRoot, '.shadcn', 'tokens.json'));
    final tokensValid = await _checkTokensFile(tokensFile);
    checks['tokens.json valid'] = tokensValid;
    _printCheck('tokens.json valid', tokensValid,
        path: tokensFile.existsSync() ? tokensFile.path : null);

    // Check 5: Sync status
    final needsSync = await _checkNeedsSync();
    checks['Sync up to date'] = !needsSync;
    _printCheck('Sync up to date', !needsSync);

    print('');
    if (checks.values.every((v) => v)) {
      print('✓ All checks passed! Studio is ready.');
      print('  Run: flutter_shadcn studio');
    } else {
      print('✗ Some checks failed.');
      if (!registryExists || needsSync) {
        print('  Fix: Run: flutter_shadcn studio --sync');
      }
    }
  }

  // Helper methods

  Future<String> _getAppPackageName() async {
    final pubspecFile = File(p.join(projectRoot, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      print('Error: pubspec.yaml not found in project root');
      exit(ExitCodes.configInvalid);
    }

    final content = await pubspecFile.readAsString();
    final nameMatch =
        RegExp(r'^name:\s*(.+)$', multiLine: true).firstMatch(content);
    if (nameMatch == null) {
      print('Error: Could not find package name in pubspec.yaml');
      exit(ExitCodes.configInvalid);
    }

    return nameMatch.group(1)!.trim();
  }

  Future<void> _copyStudioTemplate(
      Directory studioDir, String appPackageName) async {
    // Get CLI package root
    final cliRoot = await _getCliRoot();
    final templateDir = Directory(p.join(cliRoot, 'templates', 'studio'));

    if (!templateDir.existsSync()) {
      print('Error: Studio template not found at: ${templateDir.path}');
      exit(ExitCodes.ioError);
    }

    print('  Copying studio template...');

    // Copy template files
    await _copyDirectory(templateDir, studioDir);

    // Generate pubspec.yaml
    final pubspecContent = _generateStudioPubspec(appPackageName);
    final pubspecFile = File(p.join(studioDir.path, 'pubspec.yaml'));
    await pubspecFile.writeAsString(pubspecContent);

    // Generate README
    final readmeContent = _generateStudioReadme();
    final readmeFile = File(p.join(studioDir.path, 'README.md'));
    await readmeFile.writeAsString(readmeContent);

    print('  ✓ Template copied');
  }

  Future<String> _getCliRoot() async {
    // Try to resolve the CLI package root
    final scriptPath = Platform.script.toFilePath();
    var current = Directory(p.dirname(scriptPath));

    // Walk up to find the CLI root (contains templates/)
    for (var i = 0; i < 5; i++) {
      final templatesDir = Directory(p.join(current.path, 'templates'));
      if (templatesDir.existsSync()) {
        return current.path;
      }
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }

    // Fallback: assume we're in bin/ and go up one level
    return p.dirname(p.dirname(scriptPath));
  }

  Future<void> _copyDirectory(Directory source, Directory dest) async {
    await for (final entity in source.list(recursive: true)) {
      final relativePath = p.relative(entity.path, from: source.path);
      final destPath = p.join(dest.path, relativePath);

      if (entity is Directory) {
        await Directory(destPath).create(recursive: true);
      } else if (entity is File) {
        await entity.copy(destPath);
      }
    }
  }

  String _generateStudioPubspec(String appPackageName) {
    return '''
name: shadcn_flutter_studio
description: Local theme studio for shadcn_flutter
version: 1.0.0
publish_to: 'none'

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_shadcn_studio_registry:
    path: ../studio_registry

dev_dependencies:
  flutter_test:
    sdk: flutter

flutter:
  uses-material-design: true
''';
  }

  String _generateStudioReadme() {
    return '''
# shadcn_flutter Studio

This is your local shadcn_flutter theme studio.

## Commands

- `flutter_shadcn studio` - Launch the studio
- `flutter_shadcn studio --sync` - Sync with installed components
- `flutter_shadcn studio --doctor` - Check installation status

## Auto-generated

This directory is managed by `flutter_shadcn_cli`.
Do not edit files here directly - they may be regenerated.
''';
  }

  Future<void> _ensureTokensFile() async {
    final tokensFile = File(p.join(projectRoot, '.shadcn', 'tokens.json'));

    if (tokensFile.existsSync()) {
      print('  tokens.json already exists');
      return;
    }

    print('  Creating default tokens.json...');
    await tokensFile.parent.create(recursive: true);

    final defaultTokens = {
      'version': 1,
      'themeMode': 'system',
      'radius': 8,
      'density': 0,
      'colors': {
        'primary': '#6D28D9',
        'background': '#FFFFFF',
        'foreground': '#0F172A',
        'border': '#E2E8F0',
      },
    };

    await tokensFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(defaultTokens),
    );
    print('  ✓ tokens.json created');
  }

  Future<List<String>> _getInstalledComponents() async {
    // Scan the components directory to find what's installed
    final config = await ShadcnConfig.load(projectRoot);
    final installPath = config.registryConfig()?.installPath ??
        config.installPath ??
        'lib/ui/shadcn';
    final componentsDir =
        Directory(p.join(projectRoot, installPath, 'components'));

    if (!componentsDir.existsSync()) {
      print('  No components directory found');
      return [];
    }

    final installed = <String>[];

    await for (final entity in componentsDir.list()) {
      if (entity is Directory) {
        final componentName = p.basename(entity.path);
        // Check if it has a main dart file or meta.json
        final mainFile = File(p.join(entity.path, '$componentName.dart'));
        final metaFile = File(p.join(entity.path, 'meta.json'));

        if (mainFile.existsSync() || metaFile.existsSync()) {
          installed.add(componentName);
        }
      }
    }

    return installed..sort();
  }

  Future<void> _generateStudioRegistry(List<String> installedComponents) async {
    final registryDir =
        Directory(p.join(projectRoot, '.shadcn', 'studio_registry'));

    print('  Generating studio registry package...');

    // Create directory structure
    await registryDir.create(recursive: true);
    final libDir = Directory(p.join(registryDir.path, 'lib'));
    await libDir.create(recursive: true);
    final componentsDir = Directory(p.join(libDir.path, 'components'));
    await componentsDir.create(recursive: true);

    // Get app package name
    final appPackageName = await _getAppPackageName();

    // Generate pubspec.yaml
    final pubspecContent = _generateRegistryPubspec(appPackageName);
    final pubspecFile = File(p.join(registryDir.path, 'pubspec.yaml'));
    await pubspecFile.writeAsString(pubspecContent);

    // Generate preview_types.dart
    final typesContent = _generatePreviewTypes();
    final typesFile = File(p.join(libDir.path, 'preview_types.dart'));
    await typesFile.writeAsString(typesContent);

    // Copy preview files from registry for installed components
    final previewImports = <String>[];
    final previewEntries = <String>[];

    if (registryRoot != null && installedComponents.isNotEmpty) {
      for (final componentId in installedComponents) {
        final previewSource = File(
          p.join(registryRoot!, 'components', componentId, 'preview.dart'),
        );

        if (previewSource.existsSync()) {
          print('    Processing preview for: $componentId');

          // Read and transform preview file
          var previewContent = await previewSource.readAsString();

          // Replace __APP_PACKAGE__ placeholder with actual package name
          previewContent =
              previewContent.replaceAll('__APP_PACKAGE__', appPackageName);

          // Write to studio_registry
          final previewDest = File(
            p.join(componentsDir.path, '${componentId}_preview.dart'),
          );
          await previewDest.writeAsString(previewContent);

          // Add to imports and entries
          final importAlias = componentId.replaceAll('-', '_');
          previewImports.add(
            "import 'components/${componentId}_preview.dart' as $importAlias;",
          );
          previewEntries.add('  $importAlias.${componentId}Preview,');
          print('    ✓ Preview loaded: $componentId');
        } else {
          print('    ℹ No preview.dart found for $componentId (skipped)');
        }
      }
    }

    // Generate preview_registry_compat.dart (studio template compatible)
    final compatContent = _generateStudioPreviewRegistry(
      installedComponents,
      previewImports,
      previewEntries,
    );
    final compatFile =
        File(p.join(libDir.path, 'preview_registry_compat.dart'));
    await compatFile.writeAsString(compatContent);

    // Generate preview_registry.dart (for studio template compatibility)
    final registryContent = _generateStudioPreviewRegistry(
      installedComponents,
      previewImports,
      previewEntries,
    );
    final registryFile = File(p.join(libDir.path, 'preview_registry.dart'));
    await registryFile.writeAsString(registryContent);

    // Also generate modern_preview_registry.dart for future use
    final modernRegistryContent = _generatePreviewRegistry(
      installedComponents,
      previewImports,
      previewEntries,
    );
    final modernRegistryFile =
        File(p.join(libDir.path, 'modern_preview_registry.dart'));
    await modernRegistryFile.writeAsString(modernRegistryContent);

    // Update studio's local preview_registry.dart to import from registry package
    final studioDir = Directory(p.join(projectRoot, '.shadcn', 'studio'));
    if (studioDir.existsSync()) {
      final studioRegistryContent =
          _generateStudioLocalPreviewRegistry(previewImports.isNotEmpty);
      final studioPreviewFile =
          File(p.join(studioDir.path, 'lib', 'preview_registry.dart'));
      await studioPreviewFile.writeAsString(studioRegistryContent);
      print('  ✓ Updated studio preview_registry.dart');
    }

    // Report preview count
    if (previewEntries.isNotEmpty) {
      print('  ✓ ${previewEntries.length} preview(s) loaded');
    }

    // Run flutter pub get
    print('  Running flutter pub get in registry package...');
    final pubGetResult = await Process.run(
      'flutter',
      ['pub', 'get'],
      workingDirectory: registryDir.path,
    );
    if (pubGetResult.exitCode != 0) {
      print('  Warning: flutter pub get failed in registry:');
      print(pubGetResult.stderr);
    }

    print('  ✓ Studio registry generated');
  }

  String _generateRegistryPubspec(String appPackageName) {
    return '''
name: flutter_shadcn_studio_registry
description: Preview registry for shadcn_flutter Studio
version: 1.0.0
publish_to: 'none'

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  $appPackageName:
    path: ../../

dev_dependencies:
  flutter_test:
    sdk: flutter
''';
  }

  String _generatePreviewTypes() {
    return '''
import 'package:flutter/material.dart';

typedef PreviewBuilder = Widget Function(BuildContext context);

 class PreviewVariant {
  final String id;
  final String title;
  final PreviewBuilder builder;
  
  const PreviewVariant({
    required this.id,
    required this.title,
    required this.builder,
  });
}

 class PreviewEntry {
  final String id;
  final String title;
  final String description;
  final String category;
  final List<String> tags;
  final String usageCode;
  final List<PreviewVariant> variants;
  final bool wip;
  final bool experimental;

  const PreviewEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.tags,
    required this.usageCode,
    required this.variants,
    this.wip = false,
    this.experimental = false,
  });
}
''';
  }

  String _generatePreviewRegistry(
    List<String> installedComponents,
    List<String> imports,
    List<String> entries,
  ) {
    final importsSection =
        imports.isEmpty ? '// No previews available yet' : imports.join('\n');
    final entriesSection = entries.isEmpty
        ? '  // Preview entries will be added as components are installed'
        : entries.join('\n');

    return '''
import 'preview_types.dart';
$importsSection

final List<PreviewEntry> kPreviewRegistry = [
$entriesSection
];

// Installed components: ${installedComponents.join(', ')}
// Total previews: ${entries.length}
''';
  }

  String _generateStudioPreviewRegistry(
    List<String> installedComponents,
    List<String> imports,
    List<String> entries,
  ) {
    // Generate adapter for studio template
    final previewAdapters = <String>[];

    // Parse imports to extract component aliases
    for (final import in imports) {
      // import 'components/button_preview.dart' as button;
      final asMatch = RegExp(r"as\s+(\w+);").firstMatch(import);
      if (asMatch != null) {
        final componentAlias = asMatch.group(1)!;
        final componentId = componentAlias.replaceAll('_', '-');
        previewAdapters.add('''
  ComponentPreview(
    id: '$componentId',
    builder: (context) => $componentAlias.${componentAlias}Preview.variants.first.builder(context),
  )''');
      }
    }

    final adaptersSection = previewAdapters.isEmpty
        ? '// No previews available yet'
        : previewAdapters.join(',\n');

    return '''
import 'package:flutter/material.dart';
${imports.join('\n')}

 class ComponentPreview {
  final String id;
  final WidgetBuilder builder;
  final bool isFallback;

  const ComponentPreview({
    required this.id,
    required this.builder,
    this.isFallback = false,
  });

  factory ComponentPreview.fallback(String id) {
    return ComponentPreview(
      id: id,
      isFallback: true,
      builder: (context) {
        return const Center(
          child: Text('No preview available'),
        );
      },
    );
  }
}

final List<ComponentPreview> previewRegistry = [
$adaptersSection
];

Widget wrapPreviewTheme(Map<String, String> values, Widget child) {
  final colors = <String, Color>{};
  for (final entry in values.entries) {
    final color = _colorFromHex(entry.value);
    if (color != null) {
      colors[entry.key] = color;
    }
  }
  if (colors.isEmpty) {
    return child;
  }
  final background = colors['background'];
  final brightness = background != null && background.computeLuminance() < 0.4
      ? Brightness.dark
      : Brightness.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: colors['primary'] ?? colors['card'] ?? Colors.blue,
    onPrimary: colors['primaryForeground'] ?? Colors.white,
    secondary: colors['secondary'] ?? colors['accent'] ?? Colors.blueGrey,
    onSecondary: colors['secondaryForeground'] ?? Colors.white,
    surface: colors['card'] ?? Colors.grey.shade900,
    onSurface: colors['cardForeground'] ?? Colors.white,
    background: background ?? Colors.black,
    onBackground: colors['foreground'] ?? Colors.white,
    error: colors['destructive'] ?? Colors.red,
    onError: colors['destructiveForeground'] ?? Colors.white,
    surfaceVariant: colors['popover'] ?? colors['card'] ?? Colors.grey,
    outline: colors['border'] ?? Colors.white.withOpacity(0.2),
    outlineVariant: colors['sidebarBorder'] ?? Colors.white24,
    shadow: Colors.black.withOpacity(0.4),
    tertiary: colors['accent'] ?? Colors.orange,
    onTertiary: colors['accentForeground'] ??
        (brightness == Brightness.dark ? Colors.white : Colors.black),
  );
  final theme = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
  );
  return Theme(
    data: theme,
    child: child,
  );
}

Color? _colorFromHex(String value) {
  final hex = value.replaceAll('#', '');
  if (hex.length == 6) {
    return Color(int.parse('FF\$hex', radix: 16));
  }
  if (hex.length == 8) {
    return Color(int.parse(hex, radix: 16));
  }
  return null;
}

// Installed components: ${installedComponents.join(', ')}
// Total previews: ${entries.length}
''';
  }

  Future<bool> _checkNeedsSync() async {
    final configFile = File(p.join(projectRoot, '.shadcn', 'config.json'));
    final lastSyncFile =
        File(p.join(projectRoot, '.shadcn', 'studio', '.last_sync'));

    if (!lastSyncFile.existsSync()) {
      return true; // Never synced
    }

    if (!configFile.existsSync()) {
      return false; // No components installed
    }

    final configModified = await configFile.lastModified();
    final lastSync = DateTime.parse(await lastSyncFile.readAsString());

    return configModified.isAfter(lastSync);
  }

  Future<bool> _checkFlutter() async {
    try {
      final result = await Process.run('flutter', ['--version']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _checkTokensFile(File tokensFile) async {
    if (!tokensFile.existsSync()) {
      return false;
    }

    try {
      final content = await tokensFile.readAsString();
      final json = jsonDecode(content);
      return json is Map && json.containsKey('version');
    } catch (e) {
      return false;
    }
  }

  void _printCheck(String label, bool passed, {String? path}) {
    final icon = passed ? '✓' : '✗';
    final status = passed ? 'PASS' : 'FAIL';
    print('  $icon $label: $status');
    if (path != null) {
      print('    $path');
    }
  }

  String _generateStudioLocalPreviewRegistry(bool hasPreviewsAvailable) {
    // Generate studio's local preview_registry.dart that imports from the registry package
    return '''
// This file re-exports preview registry from the studio_registry package
// Auto-generated by flutter_shadcn studio sync

export 'package:flutter_shadcn_studio_registry/preview_registry_compat.dart';
''';
  }
}
