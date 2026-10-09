import 'package:flutter_shadcn_cli/src/application/services/lockfile/lock_file_exception.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/lock_json.dart';

final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

bool _isSha256(String value) =>
    _sha256Pattern.hasMatch(value.trim().toLowerCase());

String? _emptyToNull(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}

/// Which registry produced an install, plus the manifest digest it was
/// installed from so `update` can report "the registry moved".
class ShadcnLockRegistry {
  const ShadcnLockRegistry({
    this.name = '',
    this.ref,
    this.manifestSha256 = '',
    this.generatedAt,
  });

  factory ShadcnLockRegistry.fromJson(
    Map<String, dynamic> json, {
    String sourcePath = kLockFileName,
  }) {
    final manifestSha = json['manifestSha256']?.toString() ?? '';
    if (manifestSha.trim().isNotEmpty && !_isSha256(manifestSha)) {
      throw LockFileException(
        '`registry.manifestSha256` is not a sha256 digest: "$manifestSha".',
        sourcePath,
      );
    }
    return ShadcnLockRegistry(
      name: json['name']?.toString() ?? '',
      ref: _emptyToNull(json['ref']?.toString()),
      manifestSha256: manifestSha.trim().toLowerCase(),
      generatedAt: _emptyToNull(json['generatedAt']?.toString()),
    );
  }

  /// Registry name, e.g. `shadcn_flutter`.
  final String name;

  /// Git ref or source label the manifest came from.
  final String? ref;

  /// sha256 of `manifests/registry.json` at install time.
  final String manifestSha256;

  /// ISO-8601 timestamp of the manifest that produced this lock.
  final String? generatedAt;

  /// True when [manifestSha256] names a different manifest than the one on
  /// disk right now.
  bool hasMoved(String currentManifestSha256) {
    if (manifestSha256.isEmpty || currentManifestSha256.isEmpty) {
      return false;
    }
    return manifestSha256.toLowerCase() != currentManifestSha256.toLowerCase();
  }

  ShadcnLockRegistry copyWith({
    String? name,
    String? ref,
    String? manifestSha256,
    String? generatedAt,
  }) {
    return ShadcnLockRegistry(
      name: name ?? this.name,
      ref: ref ?? this.ref,
      manifestSha256: manifestSha256 ?? this.manifestSha256,
      generatedAt: generatedAt ?? this.generatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (ref != null) 'ref': ref,
      'manifestSha256': manifestSha256,
      if (generatedAt != null) 'generatedAt': generatedAt,
    };
  }
}

/// The generated `theme/app_theme.dart` selected by `init` or `theme apply`.
class LockThemeSelection {
  const LockThemeSelection({
    required this.id,
    required this.path,
    this.sha256 = '',
  });

  factory LockThemeSelection.fromJson(
    Map<String, dynamic> json, {
    String sourcePath = kLockFileName,
  }) {
    final sha = json['sha256']?.toString() ?? '';
    if (sha.trim().isNotEmpty && !_isSha256(sha)) {
      throw LockFileException(
        '`theme.sha256` is not a sha256 digest: "$sha".',
        sourcePath,
      );
    }
    return LockThemeSelection(
      id: json['id']?.toString() ?? '',
      path: normalizeLockPath(json['path']?.toString() ?? ''),
      sha256: sha.trim().toLowerCase(),
    );
  }

  /// Theme preset id from the manifest, e.g. `vercel`.
  final String id;

  /// Project relative path of the generated theme file.
  final String path;

  /// sha256 of the generated file.
  final String sha256;

  Map<String, dynamic> toJson() {
    return {'id': id, 'path': path, 'sha256': sha256};
  }
}

/// Installed layer state: the unit ids pulled in by the closure and the
/// project relative path -> sha256 of every file written for them.
class LockLayerState {
  const LockLayerState({this.units = const [], this.files = const {}});

  factory LockLayerState.fromJson(
    Map<String, dynamic> json, {
    String sourcePath = kLockFileName,
  }) {
    final layer = json['layer']?.toString() ?? 'layer';
    return LockLayerState(
      units: lockSortedList(lockStringList(json['units'])),
      files: lockHashMap(json['files'], 'layers.$layer.files', sourcePath),
    );
  }

  final List<String> units;
  final Map<String, String> files;

  bool get isEmpty => units.isEmpty && files.isEmpty;

  /// Union with [other]; [other]'s hashes win because it was written last.
  LockLayerState mergeWith(LockLayerState other) {
    return LockLayerState(
      units: lockSortedList([...units, ...other.units]),
      files: {...files, ...other.files},
    );
  }

  LockLayerState withUnit(String unit) {
    return LockLayerState(
        units: lockSortedList([...units, unit]), files: files);
  }

  LockLayerState withFile(String path, String sha256) {
    return LockLayerState(
      units: units,
      files: {...files, normalizeLockPath(path): sha256},
    );
  }

  LockLayerState copyWith({List<String>? units, Map<String, String>? files}) {
    return LockLayerState(
      units: units ?? this.units,
      files: files ?? this.files,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'units': lockSortedList(units),
      'files': lockSortedStringMap(files),
    };
  }
}
