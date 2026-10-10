import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_unit.dart';

/// Component models from the generated `manifests/registry.json`.
///
/// One component entry per registry directory under `components/<id>/`
/// (118 entries post-cutover).

/// The `deps` block of a component. Exactly the four layer keys;
/// `check_layers` in the kit generator enforces that they equal the real
/// imports of the component's files.
class ManifestComponentDeps {
  final List<String> foundation;
  final List<String> theme;
  final List<String> primitives;
  final List<String> components;

  const ManifestComponentDeps({
    this.foundation = const [],
    this.theme = const [],
    this.primitives = const [],
    this.components = const [],
  });

  factory ManifestComponentDeps.fromJson(Map<String, dynamic> json) {
    return ManifestComponentDeps(
      foundation: ManifestUnit.pathListFromJson(json['foundation']),
      theme: ManifestUnit.pathListFromJson(json['theme']),
      primitives: ManifestUnit.pathListFromJson(json['primitives']),
      components: ManifestUnit.pathListFromJson(json['components']),
    );
  }
}

/// Free-form public-symbol summary (the meta.json `api` block).
///
/// Values are either a list of symbol names or a named group of lists; keys
/// are free-form (`classes`, `enums`, `constants`, `functions`, `typedefs`,
/// `extensions`, `mixins`, `types`, `abstractClasses`, ...). The CLI uses
/// the flattened names for the single-owner preflight.
class ManifestApi {
  final Map<String, Object> groups;

  const ManifestApi([this.groups = const {}]);

  factory ManifestApi.fromJson(Object? json) {
    if (json is! Map) {
      return const ManifestApi();
    }
    return ManifestApi(
      json.map((key, value) => MapEntry(key.toString(), value as Object)),
    );
  }

  /// Every symbol name declared by this component, flattened across groups.
  Set<String> get symbolNames {
    final names = <String>{};
    for (final value in groups.values) {
      if (value is List) {
        names.addAll(value.whereType<String>());
      } else if (value is Map) {
        for (final inner in value.values) {
          if (inner is List) {
            names.addAll(inner.whereType<String>());
          }
        }
      }
    }
    return names;
  }
}

/// The component `theme` section (kept for Studio; may be null).
///
/// `userFile` may point at another component's theme file (`owner`); a
/// component with no theme class has `class: null`. Keys beyond the known
/// ones are free-form and preserved in [extra].
class ManifestComponentTheme {
  final String? className;
  final String? userFile;
  final String? owner;
  final Map<String, dynamic> extra;

  const ManifestComponentTheme({
    this.className,
    this.userFile,
    this.owner,
    this.extra = const {},
  });

  factory ManifestComponentTheme.fromJson(Map<String, dynamic> json) {
    final rest = Map<String, dynamic>.from(json);
    return ManifestComponentTheme(
      className: rest.remove('class') as String?,
      userFile: rest.remove('userFile') as String?,
      owner: rest.remove('owner') as String?,
      extra: rest,
    );
  }
}

/// One installable component from the manifest `components` map.
class ManifestComponent {
  final String id;
  final String name;
  final String category;
  final String description;
  final String entry;
  final List<String> files;
  final List<String> userOwned;
  final ManifestComponentDeps deps;
  final List<String> tags;
  final ManifestApi api;
  final ManifestComponentTheme? theme;
  final String? install;
  final String? import;
  final List<PackageRef> packages;

  const ManifestComponent({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.entry,
    required this.files,
    required this.userOwned,
    required this.deps,
    required this.tags,
    required this.api,
    required this.theme,
    this.install,
    this.import,
    this.packages = const [],
  });

  factory ManifestComponent.fromJson(String id, Map<String, dynamic> json) {
    return ManifestComponent(
      id: id,
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      description: json['description'] as String? ?? '',
      entry: json['entry'] as String? ?? '',
      files: ManifestUnit.pathListFromJson(json['files']),
      userOwned: ManifestUnit.pathListFromJson(json['userOwned']),
      deps: json['deps'] is Map
          ? ManifestComponentDeps.fromJson(
              (json['deps'] as Map)
                  .map((key, value) => MapEntry(key.toString(), value)),
            )
          : const ManifestComponentDeps(),
      tags: ManifestUnit.pathListFromJson(json['tags']),
      api: ManifestApi.fromJson(json['api']),
      theme: json['theme'] is Map
          ? ManifestComponentTheme.fromJson(
              (json['theme'] as Map)
                  .map((key, value) => MapEntry(key.toString(), value)),
            )
          : null,
      install: json['install'] as String?,
      import: json['import'] as String?,
      packages: PackageRef.listFromJson(json['packages']),
    );
  }

  /// All registry-owned relPaths of this component (files + userOwned).
  List<String> get allFiles => [...files, ...userOwned];
}
