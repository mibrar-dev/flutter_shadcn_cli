import 'package:path/path.dart' as p;

class PathEscapeException implements Exception {
  final String root;
  final String targetPath;

  const PathEscapeException({
    required this.root,
    required this.targetPath,
  });

  @override
  String toString() => 'Path escapes root: $targetPath';
}

class FilesystemGuard {
  const FilesystemGuard();

  void assertWithinRoot({required String root, required String targetPath}) {
    final normalizedRoot = p.normalize(root);
    final normalizedTarget = p.normalize(targetPath);
    if (normalizedTarget != normalizedRoot &&
        !p.isWithin(normalizedRoot, normalizedTarget)) {
      throw PathEscapeException(root: normalizedRoot, targetPath: targetPath);
    }
  }
}
