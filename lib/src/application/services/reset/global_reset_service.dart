import 'dart:io';

import 'package:path/path.dart' as p;

class GlobalResetResult {
  final List<String> deletedRelativePaths;

  const GlobalResetResult({required this.deletedRelativePaths});
}

class GlobalResetService {
  final String homeDirectory;

  const GlobalResetService({required this.homeDirectory});

  Future<GlobalResetResult> reset() async {
    final cliHome = Directory(p.join(homeDirectory, '.flutter_shadcn'));
    const managedPaths = <String>[
      'cache',
      'crashes',
      'project-resets',
    ];

    final deleted = <String>[];
    for (final relativePath in managedPaths) {
      final target = Directory(p.join(cliHome.path, relativePath));
      if (await target.exists()) {
        await target.delete(recursive: true);
        deleted.add(relativePath);
      }
    }

    return GlobalResetResult(deletedRelativePaths: deleted);
  }
}
