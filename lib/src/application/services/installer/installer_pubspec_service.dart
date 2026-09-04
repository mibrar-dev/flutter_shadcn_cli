import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer_dependency_update_result.dart';
import 'package:flutter_shadcn_cli/src/application/services/pubspec/pubspec_change_planner.dart';
import 'package:flutter_shadcn_cli/src/application/services/pubspec/pubspec_editor.dart';
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

    final content = pubspecFile.readAsStringSync();
    final result = applyDependencies(content.split('\n'), deps);
    if (result.conflicts.isNotEmpty) {
      throw PubspecUpdateException(
        code: 'dependency-conflict',
        message: formatDependencyConflicts(result.conflicts),
      );
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
      throw PubspecUpdateException(
        code: 'dependency-conflict',
        message: formatDependencyConflicts(result.conflicts),
      );
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

  Future<void> updateFonts(List<FontEntry> fonts) async {
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

  String _resolveProjectPath(String relativePath) {
    return ProjectPathGuard.resolveSafeWritePath(
      projectRoot: targetDir,
      destinationRelativePath: relativePath,
    );
  }
}

class PubspecUpdateException implements Exception {
  final String code;
  final String message;

  const PubspecUpdateException({
    required this.code,
    required this.message,
  });

  @override
  String toString() => 'PubspecUpdateException($code): $message';
}
