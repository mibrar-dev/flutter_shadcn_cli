import 'package:flutter_shadcn_cli/src/application/services/lockfile/lock_file_exception.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/lock_json.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/lock_layer.dart';

/// The `deps` block of an installed component, mirrored from the manifest so
/// the closure can be reasoned about (and audited) without re-reading the
/// registry.
class LockComponentDeps {
  const LockComponentDeps({
    this.foundation = const [],
    this.theme = const [],
    this.primitives = const [],
    this.components = const [],
  });

  factory LockComponentDeps.fromJson(
    Map<String, dynamic> json, {
    String sourcePath = kLockFileName,
  }) {
    return LockComponentDeps(
      foundation: lockSortedList(lockStringList(json['foundation'])),
      theme: lockSortedList(lockStringList(json['theme'])),
      primitives: lockSortedList(lockStringList(json['primitives'])),
      components: lockSortedList(lockStringList(json['components'])),
    );
  }

  final List<String> foundation;
  final List<String> theme;
  final List<String> primitives;
  final List<String> components;

  /// The unit ids this component needs from [layer].
  List<String> forLayer(LockLayer layer) {
    return switch (layer) {
      LockLayer.foundation => foundation,
      LockLayer.theme => theme,
      LockLayer.primitives => primitives,
    };
  }

  /// True when [unit] of [layer] is part of this component's closure.
  bool references(LockLayer layer, String unit) {
    return forLayer(layer).contains(unit);
  }

  /// Union of every layer unit id.
  Set<String> get layerUnits => {
        for (final layer in LockLayer.values) ...forLayer(layer),
      };

  /// Union with [other]; a layer unit stays until no component needs it.
  LockComponentDeps mergeWith(LockComponentDeps other) {
    return LockComponentDeps(
      foundation: lockSortedList([...foundation, ...other.foundation]),
      theme: lockSortedList([...theme, ...other.theme]),
      primitives: lockSortedList([...primitives, ...other.primitives]),
      components: lockSortedList([...components, ...other.components]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'foundation': lockSortedList(foundation),
      'theme': lockSortedList(theme),
      'primitives': lockSortedList(primitives),
      'components': lockSortedList(components),
    };
  }
}

/// Public symbol summary of an installed component, copied from the manifest
/// `api` block so the single-owner preflight runs from the lock alone.
class LockComponentApi {
  const LockComponentApi({this.byKind = const {}});

  factory LockComponentApi.fromJson(Map<String, dynamic> json) {
    final byKind = <String, List<String>>{};
    json.forEach((key, value) {
      if (value is List) {
        byKind[key] = lockStringList(value);
        return;
      }
      if (value is Map) {
        // Map groups (`providedByPrimitives`, `reExportedFromComponents`)
        // name the owning unit, not symbols this component defines.
        return;
      }
      if (value is String) {
        byKind[key] = [value];
      }
    });
    return LockComponentApi(byKind: byKind);
  }

  /// Api kinds that never denote owned symbols.
  static const nonOwnedKinds = <String>{
    'providedByPrimitives',
    'reExportedFromComponents',
    'providedBy',
    'reusedFrom',
  };

  /// Free-form kind (`classes`, `enums`, `constants`, ...) -> symbols.
  final Map<String, List<String>> byKind;

  List<String> symbolsFor(String kind) => byKind[kind] ?? const [];

  /// Every owned symbol across definition kinds (non-owned kinds such as
  /// `providedByPrimitives` are excluded so old locks stay safe).
  Set<String> get symbols => {
        for (final entry in byKind.entries)
          if (!nonOwnedKinds.contains(entry.key)) ...entry.value,
      };

  /// True when [symbol] would be declared by this component.
  bool declares(String symbol) => symbols.contains(symbol);

  LockComponentApi mergeWith(LockComponentApi other) {
    final merged = <String, List<String>>{};
    for (final entry in {...byKind, ...other.byKind}.entries) {
      merged[entry.key] = lockSortedList([
        ...(byKind[entry.key] ?? const <String>[]),
        ...(other.byKind[entry.key] ?? const <String>[]),
      ]);
    }
    return LockComponentApi(byKind: merged);
  }

  Map<String, dynamic> toJson() => lockSortedNestedMap(byKind);
}

/// One installed component: the files the CLI wrote, the files the user owns,
/// its closure and its public symbols.
///
/// [files] and [userOwned] are disjoint by construction: a user-owned file is
/// never reported as updatable, and a path that appears in both is a corrupt
/// lock rather than a silent overwrite.
class ShadcnLockComponent {
  ShadcnLockComponent({
    required this.id,
    this.version,
    Map<String, String> files = const {},
    Map<String, String> userOwned = const {},
    this.deps = const LockComponentDeps(),
    this.api = const LockComponentApi(),
    String sourcePath = kLockFileName,
  })  : files = _cleanHashes(files, sourcePath),
        userOwned = _cleanHashes(userOwned, sourcePath) {
    if (id.trim().isEmpty) {
      throw LockFileException(
        'A component entry is missing its `id`.',
        sourcePath,
      );
    }
    final overlap = files.keys.toSet().intersection(userOwned.keys.toSet());
    if (overlap.isNotEmpty) {
      throw LockFileException(
        'Component `$id` lists ${overlap.join(', ')} in both `files` and '
        '`userOwned`; a user-owned file can never be registry-owned.',
        sourcePath,
      );
    }
  }

  factory ShadcnLockComponent.fromJson(
    Map<String, dynamic> json, {
    String sourcePath = kLockFileName,
  }) {
    final id = json['id']?.toString() ?? '';
    return ShadcnLockComponent(
      id: id,
      version: json['version']?.toString(),
      files: lockHashMap(json['files'], 'components[$id].files', sourcePath),
      userOwned: lockHashMap(
        json['userOwned'],
        'components[$id].userOwned',
        sourcePath,
      ),
      deps: json['deps'] is Map<String, dynamic>
          ? LockComponentDeps.fromJson(
              json['deps']! as Map<String, dynamic>,
              sourcePath: sourcePath,
            )
          : const LockComponentDeps(),
      api: json['api'] is Map<String, dynamic>
          ? LockComponentApi.fromJson(json['api']! as Map<String, dynamic>)
          : const LockComponentApi(),
      sourcePath: sourcePath,
    );
  }

  static Map<String, String> _cleanHashes(
    Map<String, String> value,
    String sourcePath,
  ) {
    return lockHashMap(value, 'component files', sourcePath);
  }

  /// Registry component id (== directory name).
  final String id;

  /// Registry version, when the manifest publishes one.
  final String? version;

  /// Project relative path -> sha256 of the bytes the CLI wrote.
  final Map<String, String> files;

  /// Project relative path -> sha256 at install time. Never rewritten.
  final Map<String, String> userOwned;

  final LockComponentDeps deps;
  final LockComponentApi api;

  List<String> get paths => lockSortedList(files.keys);
  List<String> get userOwnedPaths => lockSortedList(userOwned.keys);

  /// Every path this component owns, registry-owned and user-owned.
  Set<String> get allPaths => {...files.keys, ...userOwned.keys};

  /// Registry-owned paths only: the set `update` is allowed to overwrite.
  Map<String, String> get updatableFiles =>
      Map.fromEntries(files.entries.where((entry) => !isUserOwned(entry.key)));

  bool isUserOwned(String path) => userOwned.containsKey(path);

  /// True when [path] belongs to this component in either role.
  bool ownsPath(String path) => allPaths.contains(path);

  /// True when this component owns at least one of [paths].
  bool ownsAny(Set<String> paths) => paths.any(ownsPath);

  ShadcnLockComponent withFile(String path, String sha256) {
    return copyWith(files: {...files, normalizeLockPath(path): sha256});
  }

  ShadcnLockComponent withUserOwnedFile(String path, String sha256) {
    final normalized = normalizeLockPath(path);
    return copyWith(
      files: Map.fromEntries(
        files.entries.where((entry) => entry.key != normalized),
      ),
      userOwned: {...userOwned, normalized: sha256},
    );
  }

  ShadcnLockComponent copyWith({
    String? id,
    String? version,
    Map<String, String>? files,
    Map<String, String>? userOwned,
    LockComponentDeps? deps,
    LockComponentApi? api,
  }) {
    return ShadcnLockComponent(
      id: id ?? this.id,
      version: version ?? this.version,
      files: files ?? this.files,
      userOwned: userOwned ?? this.userOwned,
      deps: deps ?? this.deps,
      api: api ?? this.api,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (version != null && version!.isNotEmpty) 'version': version,
      'files': lockSortedStringMap(files),
      'userOwned': lockSortedStringMap(userOwned),
      'deps': deps.toJson(),
      'api': api.toJson(),
    };
  }
}
