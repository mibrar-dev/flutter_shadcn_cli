import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_unit.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';

/// Raised when a component or unit id referenced by a closure is not in the
/// manifest. Clean break: there is no fallback resolution and no v1 graph.
class ManifestClosureException implements Exception {
  const ManifestClosureException(this.kind, this.id, {this.referencedBy});

  /// `component`, `primitive`, `foundation` or `theme`.
  final String kind;

  /// The unknown id.
  final String id;

  /// The component whose dependency block referenced [id], when known.
  final String? referencedBy;

  @override
  String toString() {
    final source =
        referencedBy == null ? '' : ' (referenced by "$referencedBy")';
    return 'Unknown $kind id "$id" in the registry manifest$source.';
  }
}

/// The transitive closure of a set of components: every component, layer unit
/// and file the install needs.
///
/// Layers are implicit (plan §1.2): foundation/theme/primitives are never
/// addressed as components, only pulled in here. The primitive graph contains
/// cycles (plan §9.7), so resolution uses a visited-set DFS and never rejects
/// a cycle; install order is irrelevant because files are copied verbatim.
class ManifestClosure {
  const ManifestClosure({
    this.components = const [],
    this.foundation = const [],
    this.theme = const [],
    this.primitives = const [],
    this.files = const [],
    this.packages = const [],
  });

  /// Component ids, sorted.
  final List<String> components;

  /// Foundation unit ids, sorted.
  final List<String> foundation;

  /// Theme unit ids, sorted.
  final List<String> theme;

  /// Primitive unit ids, sorted.
  final List<String> primitives;

  /// Registry-relative copyable files (foundation/theme/primitives/components),
  /// sorted. Excludes `themes/` JSON and user-owned files.
  final List<String> files;

  /// Union of the `packages` declared by every unit and component in the
  /// closure, sorted by name (plan §9.1).
  final List<PackageRef> packages;

  bool get isEmpty =>
      components.isEmpty &&
      foundation.isEmpty &&
      theme.isEmpty &&
      primitives.isEmpty;

  Map<String, dynamic> toJson() {
    return {
      'components': components,
      'foundation': foundation,
      'theme': theme,
      'primitives': primitives,
      'files': files,
      'packages': packages
          .map(
            (package) => {
              'name': package.name,
              if (package.sdk) 'sdk': true,
              if (package.constraint != null) 'constraint': package.constraint,
            },
          )
          .toList(),
    };
  }
}

/// Resolves the component + layer closure from a [RegistryManifest].
class ManifestClosureResolver {
  const ManifestClosureResolver(this.manifest);

  final RegistryManifest manifest;

  /// Transitive closure of [componentIds].
  ///
  /// [includeCore] adds every foundation and theme unit (the always-on core
  /// `init` copies, plan §2.1); `add` keeps it on so the layer core is present
  /// even on a project that was never `init`ed.
  ManifestClosure resolve(
    Iterable<String> componentIds, {
    bool includeCore = true,
  }) {
    final components = <String>{};
    final primitives = <String>{};
    final foundation = <String>{};
    final theme = <String>{};

    final queue = <String>[];
    for (final raw in componentIds) {
      final id = raw.trim();
      if (id.isEmpty) {
        continue;
      }
      _requireComponent(id);
      if (components.add(id)) {
        queue.add(id);
      }
    }

    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      final component = manifest.components[id]!;
      for (final dep in component.deps.components) {
        _requireComponent(dep, referencedBy: id);
        if (components.add(dep)) {
          queue.add(dep);
        }
      }
      for (final dep in component.deps.primitives) {
        _addPrimitive(dep, primitives, referencedBy: id);
      }
      for (final dep in component.deps.foundation) {
        _requireFoundation(dep, referencedBy: id);
        foundation.add(dep);
      }
      for (final dep in component.deps.theme) {
        _requireTheme(dep, referencedBy: id);
        theme.add(dep);
      }
    }

    if (includeCore) {
      foundation.addAll(manifest.foundation.keys);
      theme.addAll(manifest.theme.keys);
    }

    return ManifestClosure(
      components: _sorted(components),
      foundation: _sorted(foundation),
      theme: _sorted(theme),
      primitives: _sorted(primitives),
      files: _sorted(_filesOf(components, primitives, foundation, theme)),
      packages: _packagesOf(components, primitives, foundation, theme),
    );
  }

  void _requireComponent(String id, {String? referencedBy}) {
    if (!manifest.components.containsKey(id)) {
      throw ManifestClosureException(
        'component',
        id,
        referencedBy: referencedBy,
      );
    }
  }

  void _requireFoundation(String id, {String? referencedBy}) {
    if (!manifest.foundation.containsKey(id)) {
      throw ManifestClosureException(
        'foundation',
        id,
        referencedBy: referencedBy,
      );
    }
  }

  void _requireTheme(String id, {String? referencedBy}) {
    if (!manifest.theme.containsKey(id)) {
      throw ManifestClosureException('theme', id, referencedBy: referencedBy);
    }
  }

  /// Cycle-tolerant DFS over the primitive graph.
  void _addPrimitive(String id, Set<String> into, {String? referencedBy}) {
    final stack = <String>[id];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (!into.add(current)) {
        continue;
      }
      final unit = manifest.primitives[current];
      if (unit == null) {
        throw ManifestClosureException(
          'primitive',
          current,
          referencedBy: referencedBy,
        );
      }
      for (final dep in unit.deps.primitives) {
        if (!into.contains(dep)) {
          stack.add(dep);
        }
      }
    }
  }

  Iterable<String> _filesOf(
    Set<String> components,
    Set<String> primitives,
    Set<String> foundation,
    Set<String> theme,
  ) {
    final files = <String>{};
    for (final id in components) {
      files.addAll(manifest.components[id]!.files);
    }
    for (final id in primitives) {
      files.addAll(manifest.primitives[id]!.files);
    }
    for (final id in foundation) {
      files.addAll(manifest.foundation[id]!.files);
    }
    for (final id in theme) {
      files.addAll(manifest.theme[id]!.files);
    }
    return files;
  }

  List<PackageRef> _packagesOf(
    Set<String> components,
    Set<String> primitives,
    Set<String> foundation,
    Set<String> theme,
  ) {
    final byName = <String, PackageRef>{};
    void collect(Iterable<PackageRef> packages) {
      for (final package in packages) {
        if (package.name.isEmpty) {
          continue;
        }
        byName.putIfAbsent(package.name, () => package);
      }
    }

    for (final id in _sorted(components)) {
      collect(manifest.components[id]!.packages);
    }
    for (final id in _sorted(primitives)) {
      collect(manifest.primitives[id]!.packages);
    }
    for (final id in _sorted(foundation)) {
      collect(manifest.foundation[id]!.packages);
    }
    for (final id in _sorted(theme)) {
      collect(manifest.theme[id]!.packages);
    }
    final names = byName.keys.toList()..sort();
    return [for (final name in names) byName[name]!];
  }

  static List<String> _sorted(Iterable<String> values) =>
      values.toSet().toList()..sort();
}
