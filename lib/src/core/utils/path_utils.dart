import 'dart:io';

import 'package:path/path.dart' as p;

class ProjectRootNotFoundException implements Exception {
  final String fromDir;

  const ProjectRootNotFoundException(this.fromDir);

  @override
  String toString() {
    return 'Could not locate Flutter project root from $fromDir '
        '(pubspec.yaml not found).';
  }
}

bool isPathTraversal(String path) {
  return path.contains('..') || path.contains('\\');
}

String findProjectRootFrom(String fromDir) {
  var current = Directory(fromDir);
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      return current.path;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw ProjectRootNotFoundException(fromDir);
    }
    current = parent;
  }
}
