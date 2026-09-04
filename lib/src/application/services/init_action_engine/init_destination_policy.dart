enum InitWriteKind { dartCode, asset, projectConfig }

class InitDestinationPolicy {
  static InitWriteKind classify(String destinationRelativePath) {
    final path = destinationRelativePath.replaceAll('\\', '/');
    if (path == 'pubspec.yaml') return InitWriteKind.projectConfig;
    if (path.startsWith('lib/')) return InitWriteKind.dartCode;
    if (path.startsWith('assets/')) return InitWriteKind.asset;
    throw Exception(
      'init action destination must be under lib/ or assets/: $destinationRelativePath',
    );
  }

  static void assertCopyDestination(String destinationRelativePath) {
    final kind = classify(destinationRelativePath);
    if (kind == InitWriteKind.projectConfig) {
      throw Exception(
        'init copy actions cannot write pubspec.yaml; use mergePubspec',
      );
    }
  }
}
