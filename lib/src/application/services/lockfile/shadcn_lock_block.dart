import 'package:flutter_shadcn_cli/src/application/services/lockfile/lock_file_exception.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/lock_json.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_component.dart';

/// One installed block (registry layer 4, P6-B2): the files the CLI wrote and
/// the closure the block needs.
///
/// A block is simpler than [ShadcnLockComponent]: it declares no public
/// symbols (so the single-owner preflight never sees one) and it has no
/// user-owned file (every byte under `blocks/<id>/` belongs to the registry,
/// so `update` may always refresh a file whose bytes still match [files]).
class ShadcnLockBlock {
  ShadcnLockBlock({
    required this.id,
    this.version,
    Map<String, String> files = const {},
    this.deps = const LockComponentDeps(),
    String sourcePath = kLockFileName,
  }) : files = _cleanHashes(files, sourcePath) {
    if (id.trim().isEmpty) {
      throw LockFileException(
        'A block entry is missing its `id`.',
        sourcePath,
      );
    }
  }

  factory ShadcnLockBlock.fromJson(
    Map<String, dynamic> json, {
    String sourcePath = kLockFileName,
  }) {
    final id = json['id']?.toString() ?? '';
    return ShadcnLockBlock(
      id: id,
      version: json['version']?.toString(),
      files: lockHashMap(json['files'], 'blocks[$id].files', sourcePath),
      deps: json['deps'] is Map<String, dynamic>
          ? LockComponentDeps.fromJson(
              json['deps']! as Map<String, dynamic>,
              sourcePath: sourcePath,
            )
          : const LockComponentDeps(),
      sourcePath: sourcePath,
    );
  }

  static Map<String, String> _cleanHashes(
    Map<String, String> value,
    String sourcePath,
  ) =>
      lockHashMap(value, 'block files', sourcePath);

  /// Registry block id (== directory name), e.g. `login-01`.
  final String id;

  /// Registry version, when the manifest publishes one.
  final String? version;

  /// Project relative path -> sha256 of the bytes the CLI wrote.
  final Map<String, String> files;

  final LockComponentDeps deps;

  List<String> get paths => lockSortedList(files.keys);

  /// True when this block owns at least one of [paths].
  bool ownsAny(Set<String> paths) => paths.any(files.containsKey);

  ShadcnLockBlock withFile(String path, String sha256) {
    return copyWith(files: {...files, normalizeLockPath(path): sha256});
  }

  ShadcnLockBlock copyWith({
    String? id,
    String? version,
    Map<String, String>? files,
    LockComponentDeps? deps,
  }) {
    return ShadcnLockBlock(
      id: id ?? this.id,
      version: version ?? this.version,
      files: files ?? this.files,
      deps: deps ?? this.deps,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (version != null && version!.isNotEmpty) 'version': version,
      'files': lockSortedStringMap(files),
      'deps': deps.toJson(),
    };
  }
}
