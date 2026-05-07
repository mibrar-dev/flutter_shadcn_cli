import 'dart:io';

import 'package:path/path.dart' as p;

class InstallTransactionRollbackException implements Exception {
  final Object originalError;
  final List<Object> rollbackErrors;

  const InstallTransactionRollbackException({
    required this.originalError,
    required this.rollbackErrors,
  });

  @override
  String toString() {
    if (rollbackErrors.isEmpty) {
      return originalError.toString();
    }
    return '$originalError; rollback failed: ${rollbackErrors.join('; ')}';
  }
}

class InstallTransaction {
  final Map<String, _FileSnapshot> _fileSnapshots = {};
  final Set<String> _createdDirs = {};
  bool _committed = false;
  bool _rolledBack = false;

  void recordFileWrite(File file) {
    final path = p.normalize(file.absolute.path);
    _fileSnapshots.putIfAbsent(path, () {
      if (file.existsSync()) {
        return _FileSnapshot(
          path: path,
          existed: true,
          bytes: file.readAsBytesSync(),
        );
      }
      return _FileSnapshot(path: path, existed: false, bytes: null);
    });
  }

  void recordFileDelete(File file) {
    recordFileWrite(file);
  }

  void recordDirectoryCreate(Directory directory) {
    final path = p.normalize(directory.absolute.path);
    if (!directory.existsSync()) {
      _createdDirs.add(path);
    }
  }

  void recordDirectoryCreateTree(Directory directory) {
    var current = Directory(p.normalize(directory.absolute.path));
    final missing = <String>[];
    while (!current.existsSync()) {
      missing.add(current.path);
      final parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      current = parent;
    }
    for (final path in missing.reversed) {
      _createdDirs.add(path);
    }
  }

  void recordDirectoryDelete(Directory directory) {
    final path = p.normalize(directory.absolute.path);
    if (!directory.existsSync()) {
      return;
    }
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File) {
        recordFileDelete(entity);
      }
    }
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is Directory) {
        _createdDirs.remove(p.normalize(entity.absolute.path));
      }
    }
    _createdDirs.remove(path);
  }

  void commit() {
    _committed = true;
  }

  Future<void> rollback() async {
    if (_committed || _rolledBack) {
      return;
    }
    _rolledBack = true;
    final errors = <Object>[];
    final files = _fileSnapshots.values.toList().reversed;
    for (final snapshot in files) {
      try {
        final file = File(snapshot.path);
        if (snapshot.existed) {
          if (!file.parent.existsSync()) {
            file.parent.createSync(recursive: true);
          }
          file.writeAsBytesSync(snapshot.bytes ?? const <int>[], flush: true);
        } else if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (e) {
        errors.add(e);
      }
    }

    final dirs = _createdDirs.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final path in dirs) {
      try {
        final dir = Directory(path);
        if (dir.existsSync() && dir.listSync().isEmpty) {
          dir.deleteSync();
        }
      } catch (e) {
        errors.add(e);
      }
    }
    if (errors.isNotEmpty) {
      throw InstallTransactionRollbackException(
        originalError: 'Rollback completed with errors',
        rollbackErrors: errors,
      );
    }
  }
}

class _FileSnapshot {
  final String path;
  final bool existed;
  final List<int>? bytes;

  const _FileSnapshot({
    required this.path,
    required this.existed,
    required this.bytes,
  });
}
