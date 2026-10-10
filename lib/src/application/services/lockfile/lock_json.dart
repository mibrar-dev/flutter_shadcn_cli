import 'package:flutter_shadcn_cli/src/application/services/lockfile/hashing.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/lock_file_exception.dart';

/// The single install-state file name for lockfileVersion 2.
const String kLockFileName = 'shadcn.lock';

/// Lock paths are project relative and always use forward slashes, on every
/// platform. Stored keys are normalised so a lock written on Windows still
/// matches on macOS and vice versa.
String normalizeLockPath(String path) {
  var normalized = path.trim().replaceAll('\\', '/');
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  return normalized;
}

/// Reads a list of strings, tolerating `null` and non-string members.
List<String> lockStringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  final entries = <String>[];
  for (final entry in value) {
    final text = entry?.toString() ?? '';
    if (text.isNotEmpty) {
      entries.add(text);
    }
  }
  return entries;
}

/// Reads an object of strings, tolerating `null` and non-string members.
Map<String, String> lockStringMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  final entries = <String, String>{};
  value.forEach((key, entry) {
    final path = normalizeLockPath(key.toString());
    final text = entry?.toString() ?? '';
    if (path.isNotEmpty && text.isNotEmpty) {
      entries[path] = text;
    }
  });
  return entries;
}

/// Reads an object of project-relative path -> sha256 digests.
///
/// A digest that is not 64 hex characters means the lock was hand edited or
/// truncated, so [LockFileException] is raised instead of silently ignoring it.
Map<String, String> lockHashMap(
  Object? value,
  String field,
  String sourcePath,
) {
  if (value == null) {
    return const {};
  }
  if (value is! Map) {
    throw LockFileException(
      '`$field` must be an object of path -> sha256.',
      sourcePath,
    );
  }
  final entries = <String, String>{};
  value.forEach((key, digest) {
    final path = normalizeLockPath(key.toString());
    final text = digest?.toString() ?? '';
    if (!FileHashing.isSha256(text)) {
      throw LockFileException(
        '`$field["$path"]` is not a sha256 digest: "$text".',
        sourcePath,
      );
    }
    entries[path] = text.trim().toLowerCase();
  });
  return entries;
}

/// Deterministic JSON for a string map: keys sorted, forward slashes kept.
Map<String, String> lockSortedStringMap(Map<String, String> value) {
  final keys = value.keys.toList()..sort();
  return {for (final key in keys) normalizeLockPath(key): value[key]!};
}

/// Deterministic JSON for a nested string map: keys and values sorted.
Map<String, dynamic> lockSortedNestedMap(Map<String, List<String>> value) {
  final keys = value.keys.toList()..sort();
  return {
    for (final key in keys)
      key: (value[key] ?? const <String>[]).toList()..sort(),
  };
}

/// Deterministic JSON for a string list: sorted and de-duplicated.
List<String> lockSortedList(Iterable<String> value) {
  return value.toSet().toList()..sort();
}
