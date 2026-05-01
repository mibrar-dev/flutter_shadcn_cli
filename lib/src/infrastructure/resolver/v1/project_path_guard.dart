import 'dart:io';

import 'package:flutter_shadcn_cli/src/infrastructure/resolver/v1/resolver_v1_exception.dart';
import 'package:path/path.dart' as p;

class ProjectPathGuard {
  static String resolveSafeWritePath({
    required String projectRoot,
    required String destinationRelativePath,
  }) {
    final rootAbs = p.normalize(p.absolute(projectRoot));
    final relative = destinationRelativePath.trim();
    if (relative.isEmpty) {
      throw ResolverV1Exception('destination path cannot be empty');
    }
    if (p.isAbsolute(relative)) {
      throw ResolverV1Exception('destination path must be project-relative');
    }

    final destinationAbs = p.normalize(p.join(rootAbs, relative));
    final withinRoot =
        destinationAbs == rootAbs || p.isWithin(rootAbs, destinationAbs);
    if (!withinRoot) {
      throw ResolverV1Exception(
        'destination escapes project root: $destinationRelativePath',
      );
    }
    final canonicalRoot = _canonicalPath(rootAbs);
    final canonicalExistingParent = _canonicalPath(
      _nearestExistingParent(destinationAbs),
    );
    final canonicalParentWithinRoot =
        canonicalExistingParent == canonicalRoot ||
            p.isWithin(canonicalRoot, canonicalExistingParent);
    if (!canonicalParentWithinRoot) {
      throw ResolverV1Exception(
        'destination escapes project root through symlink: $destinationRelativePath',
      );
    }

    if (FileSystemEntity.typeSync(destinationAbs, followLinks: false) !=
        FileSystemEntityType.notFound) {
      final canonicalDestination = _canonicalPath(destinationAbs);
      final canonicalDestinationWithinRoot =
          canonicalDestination == canonicalRoot ||
              p.isWithin(canonicalRoot, canonicalDestination);
      if (!canonicalDestinationWithinRoot) {
        throw ResolverV1Exception(
          'destination escapes project root through symlink: $destinationRelativePath',
        );
      }
    }
    return destinationAbs;
  }

  static String _canonicalPath(String path) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    final resolved = switch (type) {
      FileSystemEntityType.directory =>
        Directory(path).resolveSymbolicLinksSync(),
      FileSystemEntityType.link => Link(path).resolveSymbolicLinksSync(),
      _ => File(path).resolveSymbolicLinksSync(),
    };
    return p.normalize(resolved);
  }

  static String _nearestExistingParent(String destinationAbs) {
    var current = p.dirname(destinationAbs);
    while (!Directory(current).existsSync()) {
      final parent = p.dirname(current);
      if (parent == current) {
        return current;
      }
      current = parent;
    }
    return current;
  }
}
