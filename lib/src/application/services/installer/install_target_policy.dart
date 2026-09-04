import 'dart:io';

import 'package:flutter_shadcn_cli/src/infrastructure/resolver/v1/project_path_guard.dart';
import 'package:path/path.dart' as p;

class InstallTargetPolicyException implements Exception {
  final String message;

  const InstallTargetPolicyException(this.message);

  @override
  String toString() => message;
}

enum InstallTargetKind { componentFile, sharedFile }

class InstallTargetPolicy {
  const InstallTargetPolicy();

  void validateFileDestination({
    required String projectRoot,
    required String namespace,
    required String installRoot,
    required String sharedRoot,
    required String destinationPath,
    required InstallTargetKind kind,
  }) {
    final destination = _normalizeProjectPath(
      projectRoot: projectRoot,
      path: destinationPath,
    );
    final root = p.normalize(p.absolute(projectRoot));
    final relativeDestination =
        p.relative(destination, from: root).replaceAll('\\', '/');
    _rejectReservedDestination(
      namespace: namespace,
      relativeDestination: relativeDestination,
    );

    final installRootPath = _normalizeProjectPath(
      projectRoot: projectRoot,
      path: installRoot,
    );
    final sharedRootPath = _normalizeProjectPath(
      projectRoot: projectRoot,
      path: sharedRoot,
    );

    final allowed = switch (kind) {
      InstallTargetKind.componentFile =>
        _containsOrSame(installRootPath, destination) ||
            _containsOrSame(sharedRootPath, destination),
      InstallTargetKind.sharedFile => _containsOrSame(
          sharedRootPath,
          destination,
        ),
    };
    if (allowed) {
      return;
    }

    final scope = kind == InstallTargetKind.sharedFile
        ? 'shared root "$sharedRoot"'
        : 'install root "$installRoot" or shared root "$sharedRoot"';
    throw InstallTargetPolicyException(
      'Registry "$namespace" file destination "$relativeDestination" is outside allowed install scope ($scope).',
    );
  }

  void validateAssetPath({
    required String namespace,
    required String assetPath,
  }) {
    final normalized = _normalizePubspecAssetPath(assetPath);
    if (!normalized.startsWith('assets/')) {
      throw InstallTargetPolicyException(
        'Asset path must be under assets/ for registry "$namespace": $assetPath',
      );
    }
  }

  String _normalizeProjectPath({
    required String projectRoot,
    required String path,
  }) {
    final root = p.normalize(p.absolute(projectRoot));
    if (p.isAbsolute(path)) {
      final normalized = p.normalize(path);
      if (normalized == root || p.isWithin(root, normalized)) {
        return ProjectPathGuard.resolveSafeWritePath(
          projectRoot: projectRoot,
          destinationRelativePath: p.relative(normalized, from: root),
        );
      }
      return ProjectPathGuard.resolveSafeWritePath(
        projectRoot: projectRoot,
        destinationRelativePath: path,
      );
    }
    return ProjectPathGuard.resolveSafeWritePath(
      projectRoot: projectRoot,
      destinationRelativePath: path,
    );
  }

  String _normalizePubspecAssetPath(String assetPath) {
    final trimmed = assetPath.trim();
    if (trimmed.isEmpty) {
      throw const InstallTargetPolicyException('Asset path cannot be empty.');
    }
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(trimmed)) {
      throw InstallTargetPolicyException(
        'Asset path cannot contain control characters: $assetPath',
      );
    }
    if (trimmed.contains('\\')) {
      throw InstallTargetPolicyException(
        'Asset path cannot contain backslashes: $assetPath',
      );
    }
    if (trimmed.contains('?') || trimmed.contains('#')) {
      throw InstallTargetPolicyException(
        'Asset path cannot contain query or fragment tokens: $assetPath',
      );
    }
    if (p.posix.isAbsolute(trimmed) || p.isAbsolute(trimmed)) {
      throw InstallTargetPolicyException(
        'Asset path must be project-relative: $assetPath',
      );
    }
    final normalized = p.posix.normalize(trimmed);
    if (normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        normalized.contains('/../')) {
      throw InstallTargetPolicyException(
        'Asset path cannot escape project root: $assetPath',
      );
    }
    return normalized;
  }

  void _rejectReservedDestination({
    required String namespace,
    required String relativeDestination,
  }) {
    final normalized = p.posix.normalize(relativeDestination).toLowerCase();
    final reserved = normalized == 'pubspec.yaml' ||
        normalized == '.shadcn/config.json' ||
        normalized == '.shadcn/state.json' ||
        normalized == 'shadcn.lock' ||
        normalized == '.git' ||
        normalized.startsWith('.git${Platform.pathSeparator}') ||
        normalized.startsWith('.git/');
    if (reserved) {
      throw InstallTargetPolicyException(
        'Registry "$namespace" cannot write reserved project file "$relativeDestination".',
      );
    }
  }

  bool _containsOrSame(String root, String destination) {
    return destination == root || p.isWithin(root, destination);
  }
}
