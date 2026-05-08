import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer_assets_update_result.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_dependency_update_result.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_fonts_update_result.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_section_range.dart';
import 'package:flutter_shadcn_cli/src/application/services/pubspec/pubspec_change_planner.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/resolver/v1/project_path_guard.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';

class InstallerPubspecService {
  final String targetDir;
  final CliLogger logger;
  final PubspecChangePlanner planner;

  const InstallerPubspecService({
    required this.targetDir,
    required this.logger,
    this.planner = const PubspecChangePlanner(),
  });

  Future<void> updateDependencies(Map<String, dynamic> deps) async {
    if (deps.isEmpty) {
      return;
    }

    final pubspecFile = File(_resolveProjectPath('pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      logger.warn('pubspec.yaml not found; skipping dependency updates.');
      return;
    }

    final lines = pubspecFile.readAsLinesSync();
    final result = applyDependencies(lines, deps);
    if (result.conflicts.isNotEmpty) {
      throw Exception(formatDependencyConflicts(result.conflicts));
    }
    if (result.added.isEmpty) {
      logger.detail('Dependencies already present.');
      return;
    }

    await pubspecFile.writeAsString(result.lines.join('\n'));
    logger.success('Added dependencies: ${result.added.join(', ')}');
  }

  Future<void> preflightDependencies(Map<String, dynamic> deps) async {
    if (deps.isEmpty) {
      return;
    }
    final pubspecFile = File(_resolveProjectPath('pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      return;
    }
    final lines = pubspecFile.readAsLinesSync();
    final result = applyDependencies(lines, deps);
    if (result.conflicts.isNotEmpty) {
      throw Exception(formatDependencyConflicts(result.conflicts));
    }
  }

  Future<void> updateAssets(List<String> assets) async {
    if (assets.isEmpty) {
      return;
    }
    final pubspecFile = File(_resolveProjectPath('pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      logger.warn('pubspec.yaml not found; skipping asset updates.');
      return;
    }

    final lines = pubspecFile.readAsLinesSync();
    final result = applyAssets(lines, assets);
    if (result.added.isEmpty) {
      logger.detail('Assets already present.');
      return;
    }

    await pubspecFile.writeAsString(result.lines.join('\n'));
    logger.success('Added assets: ${result.added.join(', ')}');
  }

  Future<void> updateFonts(List<FontEntry> fonts) async {
    if (fonts.isEmpty) {
      return;
    }
    final pubspecFile = File(_resolveProjectPath('pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      logger.warn('pubspec.yaml not found; skipping font updates.');
      return;
    }

    final lines = pubspecFile.readAsLinesSync();
    final result = applyFonts(lines, fonts);
    if (result.added.isEmpty) {
      logger.detail('Fonts already present.');
      return;
    }

    await pubspecFile.writeAsString(result.lines.join('\n'));
    logger.success('Added font families: ${result.added.join(', ')}');
  }

  InstallerDependencyUpdateResult applyDependencies(
    List<String> lines,
    Map<String, dynamic> deps,
  ) {
    final plan = planner.planAddDependencies(lines, deps);
    return InstallerDependencyUpdateResult(
      plan.lines,
      plan.added.keys.toList()..sort(),
      plan.conflicts,
    );
  }

  String formatDependencyConflicts(
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

  InstallerAssetsUpdateResult applyAssets(
    List<String> lines,
    List<String> assets,
  ) {
    final normalized = assets.where((a) => a.trim().isNotEmpty).toSet().toList()
      ..sort();
    if (normalized.isEmpty) {
      return InstallerAssetsUpdateResult(lines, const []);
    }

    final flutterRange = _findFlutterSection(lines);
    if (flutterRange.start == -1) {
      final addedLines = <String>[
        'flutter:',
        '  assets:',
        ...normalized.map((a) => '    - $a'),
      ];
      return InstallerAssetsUpdateResult(
        [...lines, if (lines.isNotEmpty) '', ...addedLines],
        normalized,
      );
    }

    final flutterIndent = _leadingSpaces(lines[flutterRange.start]);
    final assetsIndex = _findSectionLine(lines, flutterRange, 'assets:');
    if (assetsIndex == -1) {
      final insertIndex = flutterRange.end;
      final assetsIndent = ' ' * (flutterIndent + 2);
      final assetItemIndent = ' ' * (flutterIndent + 4);
      final insertion = <String>[
        '${assetsIndent}assets:',
        ...normalized.map((a) => '$assetItemIndent- $a'),
      ];
      final updated = [...lines]..insertAll(insertIndex, insertion);
      return InstallerAssetsUpdateResult(updated, normalized);
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
      return InstallerAssetsUpdateResult(lines, const []);
    }
    final updated = [...lines]
      ..insertAll(insertAt, additions.map((a) => '$assetItemIndent- $a'));
    return InstallerAssetsUpdateResult(updated, additions);
  }

  InstallerFontsUpdateResult applyFonts(
    List<String> lines,
    List<FontEntry> fonts,
  ) {
    if (fonts.isEmpty) {
      return InstallerFontsUpdateResult(lines, const []);
    }

    final flutterRange = _findFlutterSection(lines);
    if (flutterRange.start == -1) {
      final addedLines = <String>['flutter:', ..._formatFontSection(fonts, 2)];
      final addedFamilies = fonts.map((f) => f.family).toList()..sort();
      return InstallerFontsUpdateResult(
        [...lines, if (lines.isNotEmpty) '', ...addedLines],
        addedFamilies,
      );
    }

    final flutterIndent = _leadingSpaces(lines[flutterRange.start]);
    final fontsIndex = _findSectionLine(lines, flutterRange, 'fonts:');
    if (fontsIndex == -1) {
      final insertIndex = flutterRange.end;
      final insertion = _formatFontSection(fonts, flutterIndent + 2);
      final updated = [...lines]..insertAll(insertIndex, insertion);
      final addedFamilies = fonts.map((f) => f.family).toList()..sort();
      return InstallerFontsUpdateResult(updated, addedFamilies);
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
      return InstallerFontsUpdateResult(lines, const []);
    }

    final insertion = _formatFontSection(additions, fontsIndentCount + 2);
    final updated = [...lines]..insertAll(fontsRange.end, insertion);
    final addedFamilies = additions.map((f) => f.family).toList()..sort();
    return InstallerFontsUpdateResult(updated, addedFamilies);
  }

  String _resolveProjectPath(String relativePath) {
    return ProjectPathGuard.resolveSafeWritePath(
      projectRoot: targetDir,
      destinationRelativePath: relativePath,
    );
  }

  InstallerSectionRange _findFlutterSection(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim() == 'flutter:' && _leadingSpaces(lines[i]) == 0) {
        final end = _findSectionEnd(lines, i, 0).end;
        return InstallerSectionRange(i, end);
      }
    }
    return const InstallerSectionRange(-1, -1);
  }

  int _findSectionLine(
    List<String> lines,
    InstallerSectionRange range,
    String key,
  ) {
    for (var i = range.start + 1; i < range.end; i++) {
      if (lines[i].trim() == key) {
        return i;
      }
    }
    return -1;
  }

  InstallerSectionRange _findSectionEnd(
    List<String> lines,
    int start,
    int indent,
  ) {
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
    return InstallerSectionRange(start, end);
  }

  List<String> _formatFontSection(List<FontEntry> fonts, int indentCount) {
    final indent = ' ' * indentCount;
    final itemIndent = ' ' * (indentCount + 2);
    final innerIndent = ' ' * (indentCount + 4);
    final assetIndent = ' ' * (indentCount + 6);
    final lines = <String>['${indent}fonts:'];
    for (final entry in fonts) {
      lines.add('$itemIndent- family: ${entry.family}');
      lines.add('${innerIndent}fonts:');
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
