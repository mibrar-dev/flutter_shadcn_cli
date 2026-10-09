/// Manifest v2 layer unit models (foundation / theme / primitives).
///
/// The generated `manifests/registry.json` describes every installable unit
/// of the registry as `id -> {files, packages?, deps?}`. Paths are relative
/// to the registry root with forward slashes (see
/// `rearch/reports/registry_manifest.v2.schema.json`).
library;

/// A pub package dependency declared by a manifest unit (plan §9.1).
///
/// Derived by the kit generator from the unit's `package:` imports;
/// `flutter_localizations` is marked `sdk: true`.
class PackageRef {
  final String name;
  final bool sdk;
  final String? constraint;

  const PackageRef({required this.name, this.sdk = false, this.constraint});

  factory PackageRef.fromJson(Map<String, dynamic> json) {
    return PackageRef(
      name: json['name'] as String? ?? '',
      sdk: json['sdk'] == true,
      constraint: json['constraint'] as String?,
    );
  }

  static List<PackageRef> listFromJson(Object? json) {
    if (json is! List) {
      return const [];
    }
    return json
        .whereType<Map>()
        .map(
          (entry) => PackageRef.fromJson(
            entry.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
  }
}

/// A foundation or theme layer unit: an id plus the exact files to copy.
class ManifestUnit {
  final String id;
  final List<String> files;
  final List<PackageRef> packages;

  const ManifestUnit({
    required this.id,
    required this.files,
    this.packages = const [],
  });

  factory ManifestUnit.fromJson(String id, Map<String, dynamic> json) {
    return ManifestUnit(
      id: id,
      files: pathListFromJson(json['files']),
      packages: PackageRef.listFromJson(json['packages']),
    );
  }

  static List<String> pathListFromJson(Object? json) {
    if (json is! List) {
      return const [];
    }
    return json.map((entry) => entry.toString()).toList();
  }
}

/// The `deps` block of a primitive unit (the only layer with internal
/// edges: 27 primitive→primitive edges measured in the kit tree).
class ManifestPrimitiveDeps {
  final List<String> primitives;

  const ManifestPrimitiveDeps({this.primitives = const []});

  factory ManifestPrimitiveDeps.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const ManifestPrimitiveDeps();
    }
    return ManifestPrimitiveDeps(
      primitives: ManifestUnit.pathListFromJson(json['primitives']),
    );
  }
}

/// A primitive unit: files plus its primitive→primitive deps.
class ManifestPrimitive extends ManifestUnit {
  final ManifestPrimitiveDeps deps;

  const ManifestPrimitive({
    required super.id,
    required super.files,
    super.packages,
    required this.deps,
  });

  factory ManifestPrimitive.fromJson(String id, Map<String, dynamic> json) {
    return ManifestPrimitive(
      id: id,
      files: ManifestUnit.pathListFromJson(json['files']),
      packages: PackageRef.listFromJson(json['packages']),
      deps:
          ManifestPrimitiveDeps.fromJson(json['deps'] as Map<String, dynamic>?),
    );
  }
}
