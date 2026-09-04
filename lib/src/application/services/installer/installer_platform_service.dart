import 'dart:io';

import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/resolver/v1/project_path_guard.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;

class InstallerPlatformService {
  final String targetDir;
  final CliLogger logger;

  const InstallerPlatformService({
    required this.targetDir,
    required this.logger,
  });

  Future<void> applyInstructions(
    Component component, {
    required ShadcnConfig? config,
  }) async {
    if (component.platform.isEmpty) {
      return;
    }
    final targets = platformTargets(config);
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

  Map<String, Map<String, String>> platformTargets(ShadcnConfig? config) {
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

  void reportPostInstall(Component component) {
    logger.section('Post-install notes for ${component.name}');
    for (final line in component.postInstall) {
      logger.info('  • $line');
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

  String _resolveProjectPath(String relativePath) {
    return ProjectPathGuard.resolveSafeWritePath(
      projectRoot: targetDir,
      destinationRelativePath: relativePath,
    );
  }
}
