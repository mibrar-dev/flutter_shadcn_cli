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
          if (_isDocumentationMeta(data)) {
            continue;
          }
          final normalized = _normalizeComponentManifest(
            data,
            baseComponent: baseComponent,
          );
          final resolved = Component.fromJson(normalized);
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
        'registry/components/$category/$id/meta.json',
      );
      candidates.add(
        'registry/components/$category/$id/$id.meta.json',
      );
    }
    candidates.add(
      'registry/components/$id/meta.json',
    );
    candidates.add(
      'registry/components/$id/$id.meta.json',
    );
    return candidates;
  }

  bool _isDocumentationMeta(Map<String, dynamic> json) {
    final schema = json[r'$schema']?.toString();
    if (schema != null && schema.contains('readme_meta.schema.json')) {
      return true;
    }
    return !json.containsKey('files') && json.containsKey('whenToUse');
  }

  Map<String, dynamic> _normalizeComponentManifest(
    Map<String, dynamic> json, {
    required Component baseComponent,
  }) {
    final normalized = Map<String, dynamic>.from(json);
    final category =
        normalized['category']?.toString() ?? baseComponent.category;
    final id = normalized['id']?.toString() ?? baseComponent.id;

    normalized['id'] = id;
    normalized['name'] = normalized['name']?.toString() ?? baseComponent.name;
    if (category != null) {
      normalized['category'] = category;
    }

    final dependencies = normalized['dependencies'];
    if (dependencies is Map) {
      normalized.putIfAbsent(
          'shared', () => _stringList(dependencies['shared']));
      normalized.putIfAbsent(
        'dependsOn',
        () => _stringList(dependencies['components']),
      );
      final pubspec = dependencies['pubspec'];
      if (pubspec is Map && !normalized.containsKey('pubspec')) {
        normalized['pubspec'] = {
          'dependencies': pubspec.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        };
      }
    }

    normalized['tags'] = _stringList(normalized['tags']);
    normalized['shared'] = _stringList(normalized['shared']);
    normalized['dependsOn'] = _stringList(normalized['dependsOn']);
    normalized['assets'] = _stringList(normalized['assets']);
    normalized['postInstall'] = _stringList(normalized['postInstall']);
    normalized['files'] = _normalizeFiles(
      normalized['files'],
      category: category,
      id: id,
    );
    normalized['fonts'] =
        normalized['fonts'] is List ? normalized['fonts'] : const <dynamic>[];
    normalized['pubspec'] = normalized['pubspec'] is Map
        ? normalized['pubspec']
        : const <String, dynamic>{};
    return normalized;
  }

  List<Map<String, dynamic>> _normalizeFiles(
    Object? files, {
    required String? category,
    required String id,
  }) {
    if (files is! List) {
      throw const FormatException('manifest files must be a list');
    }
    return files.map((entry) {
      if (entry is String) {
        final componentRoot = category != null && category.isNotEmpty
            ? 'registry/components/$category/$id'
            : 'registry/components/$id';
        final destinationRoot = category != null && category.isNotEmpty
            ? '{installPath}/components/$category/$id'
            : '{installPath}/components/$id';
        return {
          'source': '$componentRoot/$entry',
          'destination': '$destinationRoot/$entry',
        };
      }
      if (entry is Map) {
        return entry.map((key, value) => MapEntry(key.toString(), value));
      }
      throw FormatException(
        'manifest file entries must be strings or objects, got ${entry.runtimeType}',
      );
    }).toList();
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map((entry) => entry.toString()).toList();
}
