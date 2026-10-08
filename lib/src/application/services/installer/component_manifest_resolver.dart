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
    normalized['version'] =
        normalized['version']?.toString() ?? baseComponent.version;

    // Merge dependency declarations from components.json (base) with the
    // local meta.json instead of letting the local file clobber the base.
    // A local manifest that omits shared/dependsOn must NOT wipe the base
    // entries, otherwise installs silently drop transitive components
    // (e.g. navigation_bar losing overflow_marquee) and produce broken
    // imports in the target project.
    final dependencies = normalized['dependencies'];
    List<String>? localShared;
    List<String>? localComponents;
    Map<String, dynamic> localPubspecDeps = const {};
    if (dependencies is Map) {
      if (dependencies.containsKey('shared')) {
        localShared = _stringList(dependencies['shared']);
      }
      if (dependencies.containsKey('components')) {
        localComponents = _stringList(dependencies['components']);
      }
      final pubspec = dependencies['pubspec'];
      if (pubspec is Map) {
        localPubspecDeps = pubspec.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    }
    // Top-level keys win over the nested `dependencies` block when both
    // are present.
    if (normalized.containsKey('shared')) {
      localShared = _stringList(normalized['shared']);
    }
    if (normalized.containsKey('dependsOn')) {
      localComponents = _stringList(normalized['dependsOn']);
    }
    if (normalized['pubspec'] is Map) {
      final raw = normalized['pubspec'] as Map;
      final nested = raw['dependencies'];
      if (nested is Map) {
        localPubspecDeps = {
          ...localPubspecDeps,
          ...nested.map((key, value) => MapEntry(key.toString(), value)),
        };
      } else {
        localPubspecDeps = {
          ...localPubspecDeps,
          ...raw.map((key, value) => MapEntry(key.toString(), value))
            ..remove('dependencies')
            ..remove('dev_dependencies'),
        };
      }
    }

    normalized['tags'] = _unionBase(
      base: baseComponent.tags,
      local: normalized.containsKey('tags')
          ? _stringList(normalized['tags'])
          : null,
    );
    normalized['shared'] = _unionBase(
      base: baseComponent.shared,
      local: localShared,
    );
    normalized['dependsOn'] = _unionBase(
      base: baseComponent.dependsOn,
      local: localComponents,
    );
    normalized['assets'] = _unionBase(
      base: baseComponent.assets,
      local: normalized.containsKey('assets')
          ? _stringList(normalized['assets'])
          : null,
    );
    normalized['postInstall'] = _unionBase(
      base: baseComponent.postInstall,
      local: normalized.containsKey('postInstall')
          ? _stringList(normalized['postInstall'])
          : null,
    );
    if (normalized.containsKey('files')) {
      normalized['files'] = _normalizeFiles(
        normalized['files'],
        category: category,
        id: id,
      );
    } else {
      // No local file list: keep the components.json file mappings so the
      // install does not lose files (or fail as malformed) just because the
      // local meta only carries metadata.
      normalized['files'] = baseComponent.files
          .map(
            (file) => {
              'source': file.source,
              'destination': file.destination,
              if (file.dependsOn.isNotEmpty)
                'dependsOn': [
                  for (final dep in file.dependsOn)
                    {'source': dep.source, 'optional': dep.optional},
                ],
            },
          )
          .toList();
    }
    if (normalized['fonts'] is! List) {
      normalized['fonts'] = [
        for (final font in baseComponent.fonts)
          {
            'family': font.family,
            'fonts': [
              for (final asset in font.fonts)
                {
                  'asset': asset.asset,
                  if (asset.weight != null) 'weight': asset.weight,
                  if (asset.style != null) 'style': asset.style,
                },
            ],
          },
      ];
    }
    final mergedPubspecDeps = <String, dynamic>{
      ..._pubspecDepsOf(baseComponent.pubspec),
      ...localPubspecDeps,
    };
    normalized['pubspec'] = {
      'dependencies': mergedPubspecDeps,
    };
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

/// Unions base (components.json) entries with local (meta.json) entries,
/// preserving base order first. A `null` local list means "not declared" and
/// keeps the base entries untouched; an explicitly declared local list is
/// merged with the base so installs never silently drop dependencies.
List<String> _unionBase({required List<String> base, List<String>? local}) {
  if (local == null) {
    return List<String>.from(base);
  }
  final merged = List<String>.from(base);
  for (final entry in local) {
    if (!merged.contains(entry)) {
      merged.add(entry);
    }
  }
  return merged;
}

Map<String, dynamic> _pubspecDepsOf(Map<String, dynamic> pubspec) {
  final nested = pubspec['dependencies'];
  if (nested is Map) {
    return nested.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}
