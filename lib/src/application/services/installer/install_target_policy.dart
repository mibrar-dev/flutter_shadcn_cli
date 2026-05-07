part of 'installer.dart';

class InstallTargetPolicyException implements Exception {
  final String message;

  const InstallTargetPolicyException(this.message);

  @override
  String toString() => message;
}

enum InstallTargetKind {
  componentFile,
  sharedFile,
}

class InstallTargetPolicy {
  const InstallTargetPolicy._();

  static void validateFileDestination({
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
    final relativeDestination = p
        .relative(destination, from: p.normalize(p.absolute(projectRoot)))
        .replaceAll('\\', '/');
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
      InstallTargetKind.sharedFile =>
        _containsOrSame(sharedRootPath, destination),
    };
    if (!allowed) {
      final scope = kind == InstallTargetKind.sharedFile
          ? 'shared root "$sharedRoot"'
          : 'install root "$installRoot" or shared root "$sharedRoot"';
      throw InstallTargetPolicyException(
        'Registry "$namespace" file destination "$relativeDestination" is outside allowed install scope ($scope).',
      );
    }
  }

  static void validateAssetPath({
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

  static String _normalizeProjectPath({
    required String projectRoot,
    required String path,
  }) {
    final rootAbs = p.normalize(p.absolute(projectRoot));
    if (p.isAbsolute(path)) {
      final normalized = p.normalize(path);
      if (normalized == rootAbs || p.isWithin(rootAbs, normalized)) {
        return ProjectPathGuard.resolveSafeWritePath(
          projectRoot: projectRoot,
          destinationRelativePath: p.relative(normalized, from: rootAbs),
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

  static String _normalizePubspecAssetPath(String assetPath) {
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
        normalized.startsWith('../') ||
        normalized == '..' ||
        normalized.contains('/../')) {
      throw InstallTargetPolicyException(
        'Asset path cannot escape project root: $assetPath',
      );
    }
    return normalized;
  }

  static void _rejectReservedDestination({
    required String namespace,
    required String relativeDestination,
  }) {
    final normalized = p.posix.normalize(relativeDestination).toLowerCase();
    final reserved = normalized == 'pubspec.yaml' ||
        normalized == '.shadcn/config.json' ||
        normalized == '.shadcn/state.json' ||
        normalized == '.git' ||
        normalized.startsWith('.git/');
    if (reserved) {
      throw InstallTargetPolicyException(
        'Registry "$namespace" cannot write reserved project file "$relativeDestination".',
      );
    }
  }

  static bool _containsOrSame(String root, String destination) {
    return destination == root || p.isWithin(root, destination);
  }
}
