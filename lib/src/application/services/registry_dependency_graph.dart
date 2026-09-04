import 'dart:convert';

import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;

class RegistryDependencyCycleException implements Exception {
  final List<String> path;

  const RegistryDependencyCycleException(this.path);

  @override
  String toString() {
    return 'Registry dependency cycle detected: ${path.join(' -> ')}';
  }
}

class RegistryDependencyMissingException implements Exception {
  final String owner;
  final String dependency;

  const RegistryDependencyMissingException({
    required this.owner,
    required this.dependency,
  });

  @override
  String toString() {
    return 'Registry dependency missing: $owner depends on $dependency';
  }
}

class RegistryDependencyGraph {
  static final RegExp _importDirectiveRegex = RegExp(
    r'''^\s*(import|export|part)\s+['"]([^'"]+)['"]''',
  );
  static final RegExp _partOfDirectiveRegex = RegExp(r'^\s*part\s+of\b');

  final Registry registry;
  final Map<String, Component> _componentsById;
  final Map<String, SharedItem> _sharedById;
  final Map<String, _FileOwner> _fileOwners;
  final Map<String, Set<String>> _sharedImportDeps = {};

  RegistryDependencyGraph(this.registry)
      : _componentsById = {
          for (final component in registry.components) component.id: component,
        },
        _sharedById = {
          for (final shared in registry.shared) shared.id: shared,
        },
        _fileOwners = _buildFileOwners(registry);

  Future<void> validateComponentInstall(
    Iterable<String> componentIds, {
    bool includeDependencies = true,
    bool allowMissing = false,
  }) async {
    final graph = await _buildGraph(
      componentIds,
      includeDependencies: includeDependencies,
      allowMissing: allowMissing,
    );
    _validateFileCycles(_reachableOwners(graph));
    _validateCycles(graph);
  }

  Future<void> validateSharedInstall(
    Iterable<String> sharedIds, {
    bool allowMissing = false,
  }) async {
    final graph = <_GraphNode, Set<_GraphNode>>{};
    for (final id in sharedIds) {
      final node = _GraphNode.shared(_normalizeSharedId(id));
      await _addSharedNode(graph, node, allowMissing: allowMissing);
    }
    _validateFileCycles(_reachableOwners(graph));
    _validateCycles(graph);
  }

  Future<Map<String, List<String>>> componentDependencyGraph(
    Iterable<String> componentIds, {
    bool includeDependencies = true,
    bool allowMissing = false,
  }) async {
    final graph = await _buildGraph(
      componentIds,
      includeDependencies: includeDependencies,
      allowMissing: allowMissing,
    );
    final result = <String, List<String>>{};
    for (final entry in graph.entries) {
      if (!entry.key.isComponent) {
        continue;
      }
      final deps = entry.value
          .where((node) => node.isComponent)
          .map((node) => node.id)
          .toList()
        ..sort();
      result[entry.key.id] = deps;
    }
    return result;
  }

  Future<Map<_GraphNode, Set<_GraphNode>>> _buildGraph(
    Iterable<String> componentIds, {
    required bool includeDependencies,
    required bool allowMissing,
  }) async {
    final graph = <_GraphNode, Set<_GraphNode>>{};
    final pending = <_GraphNode>[
      for (final id in componentIds) _GraphNode.component(id),
    ];
    final visited = <_GraphNode>{};

    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      if (!visited.add(node)) {
        continue;
      }
      if (node.isComponent) {
        final next = await _addComponentNode(
          graph,
          node,
          includeDependencies: includeDependencies,
          allowMissing: allowMissing,
        );
        pending.addAll(next);
      } else {
        final next = await _addSharedNode(
          graph,
          node,
          allowMissing: allowMissing,
        );
        pending.addAll(next);
      }
    }

    return graph;
  }

  Future<Set<_GraphNode>> _addComponentNode(
    Map<_GraphNode, Set<_GraphNode>> graph,
    _GraphNode node, {
    required bool includeDependencies,
    required bool allowMissing,
  }) async {
    final component = _componentsById[node.id];
    if (component == null) {
      if (allowMissing) {
        return const {};
      }
      throw RegistryDependencyMissingException(
        owner: 'component ${node.id}',
        dependency: node.id,
      );
    }

    final deps = graph.putIfAbsent(node, () => <_GraphNode>{});
    if (includeDependencies) {
      for (final dep in component.dependsOn) {
        if (!_componentsById.containsKey(dep)) {
          if (allowMissing) {
            continue;
          }
          throw RegistryDependencyMissingException(
            owner: 'component ${component.id}',
            dependency: dep,
          );
        }
        deps.add(_GraphNode.component(dep));
      }
    }
    for (final sharedId in component.shared) {
      final normalized = _normalizeSharedId(sharedId);
      if (_sharedById.containsKey(normalized)) {
        deps.add(_GraphNode.shared(normalized));
      } else if (_componentsById.containsKey(normalized)) {
        deps.add(_GraphNode.component(normalized));
      } else {
        if (allowMissing) {
          continue;
        }
        throw RegistryDependencyMissingException(
          owner: 'component ${component.id}',
          dependency: sharedId,
        );
      }
    }
    for (final file in component.files) {
      for (final dep in file.dependsOn) {
        if (dep.optional) {
          continue;
        }
        final owner = _fileOwners[_normalizeRegistryPath(dep.source)];
        if (owner == null) {
          throw RegistryDependencyMissingException(
            owner: 'component ${component.id}',
            dependency: dep.source,
          );
        }
        if (owner.isShared) {
          deps.add(_GraphNode.shared(owner.id));
        } else if (owner.id != component.id && includeDependencies) {
          deps.add(_GraphNode.component(owner.id));
        }
      }
    }
    return deps;
  }

  Future<Set<_GraphNode>> _addSharedNode(
    Map<_GraphNode, Set<_GraphNode>> graph,
    _GraphNode node, {
    required bool allowMissing,
  }) async {
    final shared = _sharedById[node.id];
    if (shared == null) {
      if (allowMissing) {
        return const {};
      }
      throw RegistryDependencyMissingException(
        owner: 'shared ${node.id}',
        dependency: node.id,
      );
    }

    final deps = graph.putIfAbsent(node, () => <_GraphNode>{});
    for (final depId in await _sharedImports(node.id)) {
      final normalized = _normalizeSharedId(depId);
      if (_sharedById.containsKey(normalized)) {
        deps.add(_GraphNode.shared(normalized));
      }
    }
    for (final file in shared.files) {
      for (final dep in file.dependsOn) {
        if (dep.optional) {
          continue;
        }
        final owner = _fileOwners[_normalizeRegistryPath(dep.source)];
        if (owner == null) {
          throw RegistryDependencyMissingException(
            owner: 'shared ${shared.id}',
            dependency: dep.source,
          );
        }
        if (owner.isShared && owner.id != shared.id) {
          deps.add(_GraphNode.shared(owner.id));
        }
      }
    }
    return deps;
  }

  Future<Set<String>> _sharedImports(String sharedId) async {
    final cached = _sharedImportDeps[sharedId];
    if (cached != null) {
      return cached;
    }
    final shared = _sharedById[sharedId];
    if (shared == null) {
      return const {};
    }
    final deps = <String>{};
    for (final file in shared.files) {
      if (!file.source.endsWith('.dart')) {
        continue;
      }
      try {
        final bytes = await registry.readSourceBytes(file.source);
        final content = utf8.decode(bytes);
        final dir = p.posix.dirname(_normalizeRegistryPath(file.source));
        for (final line in content.split('\n')) {
          if (_partOfDirectiveRegex.hasMatch(line)) {
            continue;
          }
          final match = _importDirectiveRegex.firstMatch(line);
          if (match == null) {
            continue;
          }
          final importPath = match.group(2);
          if (importPath == null || !importPath.startsWith('.')) {
            continue;
          }
          final resolved = p.posix.normalize(p.posix.join(dir, importPath));
          final owner = _fileOwners[resolved];
          if (owner != null && owner.isShared) {
            deps.add(owner.id);
          }
        }
      } catch (_) {
        continue;
      }
    }
    _sharedImportDeps[sharedId] = deps;
    return deps;
  }

  void _validateCycles(Map<_GraphNode, Set<_GraphNode>> graph) {
    final visiting = <_GraphNode>{};
    final visited = <_GraphNode>{};
    final path = <_GraphNode>[];

    void visit(_GraphNode node) {
      if (visited.contains(node)) {
        return;
      }
      final cycleStart = path.indexOf(node);
      if (cycleStart != -1) {
        final cycle = [
          ...path.sublist(cycleStart).map((entry) => entry.label),
          node.label,
        ];
        throw RegistryDependencyCycleException(cycle);
      }
      if (!visiting.add(node)) {
        return;
      }
      path.add(node);
      final next = graph[node]?.toList() ?? const <_GraphNode>[];
      next.sort((a, b) => a.label.compareTo(b.label));
      for (final dep in next) {
        visit(dep);
      }
      path.removeLast();
      visiting.remove(node);
      visited.add(node);
    }

    final nodes = graph.keys.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    for (final node in nodes) {
      visit(node);
    }
  }

  Set<_FileOwner> _reachableOwners(Map<_GraphNode, Set<_GraphNode>> graph) {
    final nodes = <_GraphNode>{};
    for (final entry in graph.entries) {
      nodes.add(entry.key);
      nodes.addAll(entry.value);
    }
    return _fileOwners.values.where((owner) {
      return nodes.contains(
        owner.isShared
            ? _GraphNode.shared(owner.id)
            : _GraphNode.component(owner.id),
      );
    }).toSet();
  }

  void _validateFileCycles(Set<_FileOwner> owners) {
    final graph = <String, Set<String>>{};
    final ownerSources = owners.map((owner) => owner.source).toSet();
    for (final owner in owners) {
      final deps = graph.putIfAbsent(owner.source, () => <String>{});
      for (final dep in owner.file.dependsOn) {
        if (dep.optional) {
          continue;
        }
        final target = _fileOwners[_normalizeRegistryPath(dep.source)];
        if (target == null) {
          throw RegistryDependencyMissingException(
            owner: '${owner.kind} ${owner.id}',
            dependency: dep.source,
          );
        }
        if (ownerSources.contains(target.source) &&
            target.kind == owner.kind &&
            target.id == owner.id) {
          deps.add(target.source);
        }
      }
    }

    final visiting = <String>{};
    final visited = <String>{};
    final path = <String>[];

    void visit(String source) {
      if (visited.contains(source)) {
        return;
      }
      final cycleStart = path.indexOf(source);
      if (cycleStart != -1) {
        throw RegistryDependencyCycleException([
          ...path.sublist(cycleStart),
          source,
        ]);
      }
      if (!visiting.add(source)) {
        return;
      }
      path.add(source);
      final next = graph[source]?.toList() ?? const <String>[];
      next.sort();
      for (final dep in next) {
        visit(dep);
      }
      path.removeLast();
      visiting.remove(source);
      visited.add(source);
    }

    final sources = graph.keys.toList()..sort();
    for (final source in sources) {
      visit(source);
    }
  }

  static Map<String, _FileOwner> _buildFileOwners(Registry registry) {
    final owners = <String, _FileOwner>{};
    for (final shared in registry.shared) {
      for (final file in shared.files) {
        final source = _normalizeRegistryPath(file.source);
        owners[source] = _FileOwner.shared(shared.id, source, file);
      }
    }
    for (final component in registry.components) {
      for (final file in component.files) {
        final source = _normalizeRegistryPath(file.source);
        owners[source] = _FileOwner.component(component.id, source, file);
      }
    }
    return owners;
  }

  static String _normalizeSharedId(String id) {
    return id == 'utils' ? 'util' : id;
  }

  static String _normalizeRegistryPath(String source) {
    return p.posix.normalize(source.replaceAll('\\', '/'));
  }
}

class _GraphNode {
  final String kind;
  final String id;

  const _GraphNode._(this.kind, this.id);

  factory _GraphNode.component(String id) => _GraphNode._('component', id);

  factory _GraphNode.shared(String id) => _GraphNode._('shared', id);

  bool get isComponent => kind == 'component';

  String get label => isComponent ? id : 'shared:$id';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _GraphNode && kind == other.kind && id == other.id;

  @override
  int get hashCode => Object.hash(kind, id);
}

class _FileOwner {
  final String id;
  final String source;
  final bool isShared;
  final RegistryFile file;

  const _FileOwner._({
    required this.id,
    required this.source,
    required this.isShared,
    required this.file,
  });

  factory _FileOwner.shared(String id, String source, RegistryFile file) =>
      _FileOwner._(
        id: id,
        source: source,
        isShared: true,
        file: file,
      );

  factory _FileOwner.component(String id, String source, RegistryFile file) =>
      _FileOwner._(
        id: id,
        source: source,
        isShared: false,
        file: file,
      );

  String get kind => isShared ? 'shared' : 'component';
}
