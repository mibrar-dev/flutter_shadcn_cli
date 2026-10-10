import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_component.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_unit.dart';

/// Block models from the generated `manifests/registry.json` `blocks` map
/// (P6-B1: registry layer 4, the shadcn "Blocks" section).
///
/// A block is a ready-made, installable screen (`login-01`, `dashboard-01`)
/// assembled from components. It may import foundation/theme/primitives/
/// components and never another block, which is why its `deps` block has
/// exactly the four keys a component declares — so it reuses
/// [ManifestComponentDeps] instead of a second shape.
///
/// A block has no `api` block (it declares no reusable public symbols) and no
/// user-owned file: the single-owner preflight therefore never sees one, and
/// `update` may always rewrite a block file whose bytes still match the lock.

/// The viewports a block may be designed for. A docs/Studio hint only: the
/// CLI never blocks an install on it.
const Set<String> manifestBlockViewports = {'desktop', 'mobile'};

/// One installable block from the manifest `blocks` map.
class ManifestBlock {
  const ManifestBlock({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.viewport,
    required this.entry,
    required this.files,
    required this.docs,
    required this.deps,
    required this.tags,
    this.install,
    this.import,
    this.packages = const [],
  });

  factory ManifestBlock.fromJson(String id, Map<String, dynamic> json) {
    return ManifestBlock(
      id: id,
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      description: json['description'] as String? ?? '',
      viewport: json['viewport'] as String? ?? '',
      entry: json['entry'] as String? ?? '',
      files: ManifestUnit.pathListFromJson(json['files']),
      docs: ManifestUnit.pathListFromJson(json['docs']),
      deps: json['deps'] is Map
          ? ManifestComponentDeps.fromJson(
              (json['deps'] as Map)
                  .map((key, value) => MapEntry(key.toString(), value)),
            )
          : const ManifestComponentDeps(),
      tags: ManifestUnit.pathListFromJson(json['tags']),
      install: json['install'] as String?,
      import: json['import'] as String?,
      packages: PackageRef.listFromJson(json['packages']),
    );
  }

  /// Registry block id (== directory name), e.g. `login-01`.
  final String id;

  final String name;

  /// One of the six block families (Dashboard, Authentication, ...).
  final String category;

  final String description;

  /// `desktop` or `mobile` (see [manifestBlockViewports]).
  final String viewport;

  /// Registry-relative entry file, `blocks/<id>/<id_underscored>.dart`.
  final String entry;

  /// Registry-relative Dart files the CLI copies into the app.
  final List<String> files;

  /// Registry-relative documentation files. Never copied into an app.
  final List<String> docs;

  final ManifestComponentDeps deps;

  final List<String> tags;

  /// The block's own install command, e.g. `flutter_shadcn add login-01`.
  final String? install;

  /// The import line an app writes, `package:<your_app>/...` placeholder.
  final String? import;

  final List<PackageRef> packages;

  /// Every copyable registry relPath of this block. Kept for symmetry with
  /// `ManifestComponent.allFiles`; a block has no user-owned file.
  List<String> get allFiles => files;
}
