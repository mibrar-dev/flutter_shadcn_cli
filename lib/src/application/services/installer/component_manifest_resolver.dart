import 'dart:convert';

import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';

class ManifestMalformedException implements Exception {
  final String componentId;
  final String manifestPath;
  final String detail;

  const ManifestMalformedException({
    required this.componentId,
    required this.manifestPath,
    required this.detail,
  });

  @override
  String toString() =>
      'Component manifest for "$componentId" at "$manifestPath" is malformed: $detail';
}

class ComponentManifestResolver {
  final Registry _registry;
  final CliLogger _logger;
  final Set<String> _registriesWithoutManifests = {};
  final Map<String, Component> _resolvedComponents = {};

  ComponentManifestResolver({
    required Registry registry,
    CliLogger? logger,
  })  : _registry = registry,
        _logger = logger ?? CliLogger();

  Component? fallbackFromRegistry(String componentId) {
    return _registry.getComponent(componentId);
  }

  Future<Component?> resolve(String componentId) async {
    final baseComponent = _registry.getComponent(componentId);
    if (baseComponent == null) {
      return null;
    }
    final cached = _resolvedComponents[baseComponent.id];
    if (cached != null) {
      return cached;
    }

    final registryKey = _registry.sourceRoot.root;
    if (_registriesWithoutManifests.contains(registryKey)) {
      return baseComponent;
    }

    final category = baseComponent.category;
    final id = baseComponent.id;

    final candidates = _buildManifestCandidates(category, id);
    for (final candidate in candidates) {
      String? content;
      try {
        content = await _registry.sourceRoot.readString(candidate);
      } catch (_) {
        continue;
      }

      try {
        final data = jsonDecode(content);
        if (data is Map<String, dynamic>) {
          final resolved = Component.fromJson(data);
          _resolvedComponents[baseComponent.id] = resolved;
          return resolved;
        }
        throw const FormatException('manifest root must be a JSON object');
      } catch (e) {
        throw ManifestMalformedException(
          componentId: baseComponent.id,
          manifestPath: candidate,
          detail: e.toString(),
        );
      }
    }

    if (!await _registryHasAnyComponentManifest()) {
      _logger.detail(
        'No component-local manifests found for registry ${_registry.sourceRoot.root}; using components.json for this process.',
      );
      _registriesWithoutManifests.add(registryKey);
    }

    return baseComponent;
  }

  Future<bool> _registryHasAnyComponentManifest() async {
    for (final component in _registry.components) {
      for (final candidate in _buildManifestCandidates(
        component.category,
        component.id,
      )) {
        try {
          await _registry.sourceRoot.readString(candidate);
          return true;
        } catch (_) {
          continue;
        }
      }
    }
    return false;
  }

  List<String> _buildManifestCandidates(String? category, String id) {
    final candidates = <String>[];
    if (category != null && category.isNotEmpty && category != 'components') {
      candidates.add(
        'registry/components/$category/$id/$id.meta.json',
      );
      candidates.add(
        'registry/components/$category/$id/meta.json',
      );
    }
    candidates.add(
      'registry/components/$id/$id.meta.json',
    );
    candidates.add(
      'registry/components/$id/meta.json',
    );
    return candidates;
  }
}
