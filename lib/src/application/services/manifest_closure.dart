import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_unit.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';

/// Raised when a component or unit id referenced by a closure is not in the
/// manifest. Clean break: there is no fallback resolution and no v1 graph.
class ManifestClosureException implements Exception {
  const ManifestClosureException(this.kind, this.id, {this.referencedBy});

  /// `component`, `block`, `primitive`, `foundation` or `theme`.
  final String kind;

  /// The unknown id.
  final String id;

  /// The component or block whose dependency block referenced [id], when known.
  final String? referencedBy;

  @override
  String toString() {
    final source =
        referencedBy == null ? '' : ' (referenced by "$referencedBy")';
    return 'Unknown $kind id "$id" in the registry manifest$source.';
  }
}

/// The transitive closure of a set of components and blocks: every component,
/// block, layer unit and file the install needs.
///
/// Layers are implicit (plan §1.2): foundation/theme/primitives are never
/// addressed as components, only pulled in here. The primitive graph contains
/// cycles (plan §9.7), so resolution uses a visited-set DFS and never rejects
/// a cycle; install order is irrelevant because files are copied verbatim.
class ManifestClosure {
  const ManifestClosure({
    this.components = const [],
    this.blocks = const [],
    this.foundation = const [],
    this.theme = const [],
    this.primitives = const [],
    this.files = const [],
    this.packages = const [],
  });

  /// Component ids, sorted.
  final List<String> components;

  /// Block ids, sorted.
  final List<String> blocks;

  /// Foundation unit ids, sorted.
  final List<String> foundation;

  /// Theme unit ids, sorted.
  final List<String> theme;

  /// Primitive unit ids, sorted.
  final List<String> primitives;

  /// Registry-relative copyable files (foundation/theme/primitives/components/
  /// blocks), sorted. Excludes `themes/` JSON, block `docs` and user-owned
  /// files.
  final List<String> files;

  /// Union of the `packages` declared by every unit, component and block in
  /// the closure, sorted by name (plan §9.1).
  final List<PackageRef> packages;

  bool get isEmpty =>
      components.isEmpty &&
      blocks.isEmpty &&
      foundation.isEmpty &&
      theme.isEmpty &&
      primitives.isEmpty;

  Map<String, dynamic> toJson() {
    return {
      'components': components,
      'blocks': blocks,
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

/// Resolves the component + block + layer closure from a [RegistryManifest].
class ManifestClosureResolver {
  const ManifestClosureResolver(this.manifest);

  final RegistryManifest manifest;

  /// Transitive closure of [ids] plus [blockIds].
  ///
  /// [ids] may name a component or a block: that is the `add <id>` contract,
  /// so `add login-01` resolves exactly like `add button`. [blockIds] is the
  /// explicit form a caller uses when it knows the ids are blocks and nothing
  /// else (`add --all --blocks`, `sync`, `project refresh`).
  ///
  /// [includeCore] adds every foundation and theme unit (the always-on core
  /// `init` copies, plan §2.1); `add` keeps it on so the layer core is present
  /// even on a project that was never `init`ed.
  ///
  /// [includeAllPrimitives] adds every primitive unit, even those no requested
  /// component uses. `add --all` sets it so the install matches the registry
  /// mirror (docs `sync_registry.sh` copies every file); selective adds keep
  /// it off so unused primitives never bloat the app.
  ///
  /// An id that names neither is a [ManifestClosureException], so a typo never
  /// silently installs nothing.
  ManifestClosure resolve(
    Iterable<String> ids, {
    Iterable<String> blockIds = const [],
    bool includeCore = true,
    bool includeAllPrimitives = false,
  }) {
    final components = <String>{};
    final blocks = <String>{};
    final primitives = <String>{};
    final foundation = <String>{};
    final theme = <String>{};

    final queue = <_Seed>[];
    for (final raw in ids) {
      _seed(raw, components, blocks, queue);
    }
    for (final raw in blockIds) {
      final id = raw.trim();
      if (id.isEmpty) {
        continue;
      }
      _requireBlock(id);
      if (blocks.add(id)) {
        queue.add(_Seed.block(id));
      }
    }

    while (queue.isNotEmpty) {
      final seed = queue.removeLast();
      final deps = switch (seed.kind) {
        _SeedKind.component => manifest.components[seed.id]!.deps,
        _SeedKind.block => manifest.blocks[seed.id]!.deps,
      };
      for (final dep in deps.components) {
        _requireComponent(dep, referencedBy: seed.id);
        if (components.add(dep)) {
          queue.add(_Seed.component(dep));
        }
      }
      for (final dep in deps.primitives) {
        _addPrimitive(dep, primitives, referencedBy: seed.id);
      }
      for (final dep in deps.foundation) {
        _requireFoundation(dep, referencedBy: seed.id);
        foundation.add(dep);
      }
      for (final dep in deps.theme) {
        _requireTheme(dep, referencedBy: seed.id);
        theme.add(dep);
      }
    }

    if (includeCore) {
      foundation.addAll(manifest.foundation.keys);
      theme.addAll(manifest.theme.keys);
    }

    if (includeAllPrimitives) {
      primitives.addAll(manifest.primitives.keys);
    }

    return ManifestClosure(
      components: _sorted(components),
      blocks: _sorted(blocks),
      foundation: _sorted(foundation),
      theme: _sorted(theme),
      primitives: _sorted(primitives),
      files: _sorted(
        _filesOf(components, blocks, primitives, foundation, theme),
      ),
      packages: _packagesOf(components, blocks, primitives, foundation, theme),
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

  /// Seeds one user-typed id: a component when the manifest has one, a block
  /// when it has that, an error when it has neither.
  ///
  /// The error names both kinds once the registry publishes blocks, so a typo
  /// on a block id is not reported as a missing component.
  void _seed(
    String raw,
    Set<String> components,
    Set<String> blocks,
    List<_Seed> queue,
  ) {
    final id = raw.trim();
    if (id.isEmpty) {
      return;
    }
    if (manifest.components.containsKey(id)) {
      _requireComponent(id);
      if (components.add(id)) {
        queue.add(_Seed.component(id));
      }
      return;
    }
    if (manifest.blocks.containsKey(id)) {
      if (blocks.add(id)) {
        queue.add(_Seed.block(id));
      }
      return;
    }
    throw ManifestClosureException(
      manifest.blocks.isEmpty ? 'component' : 'component or block',
      id,
    );
  }

  void _requireBlock(String id, {String? referencedBy}) {
    if (!manifest.blocks.containsKey(id)) {
      throw ManifestClosureException(
        'block',
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
    Set<String> blocks,
    Set<String> primitives,
    Set<String> foundation,
    Set<String> theme,
  ) {
    final files = <String>{};
    for (final id in components) {
      files.addAll(manifest.components[id]!.files);
    }
    for (final id in blocks) {
      files.addAll(manifest.blocks[id]!.files);
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
    Set<String> blocks,
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
    for (final id in _sorted(blocks)) {
      collect(manifest.blocks[id]!.packages);
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

enum _SeedKind { component, block }

/// One queue entry: an id plus which map it came from.
class _Seed {
  const _Seed.component(this.id) : kind = _SeedKind.component;
  const _Seed.block(this.id) : kind = _SeedKind.block;

  final String id;
  final _SeedKind kind;
}
