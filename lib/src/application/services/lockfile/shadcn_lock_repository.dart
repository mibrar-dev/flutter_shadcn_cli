import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:path/path.dart' as p;

class ShadcnLockRepository {
  final String projectRoot;

  const ShadcnLockRepository(this.projectRoot);

  File get file => File(p.join(projectRoot, 'shadcn.lock'));

  Future<ShadcnLock> load() async {
    if (!await file.exists()) {
      return const ShadcnLock();
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('shadcn.lock must contain a JSON object.');
    }
    return ShadcnLock.fromJson(decoded);
  }

  Future<ShadcnLock> loadOrSynthesize() async {
    if (await file.exists()) {
      return load();
    }
    return synthesizeFromLegacyManifests();
  }

  Future<ShadcnLock> synthesizeFromLegacyManifests() async {
    final componentsDir = Directory(
      p.join(projectRoot, '.shadcn', 'components'),
    );
    if (!await componentsDir.exists()) {
      return const ShadcnLock();
    }

    final config = await ShadcnConfig.load(projectRoot);
    final namespace = config.effectiveDefaultNamespace;
    final installPath = config.installPath ?? 'lib/ui/shadcn';
    var lock = const ShadcnLock();
    await for (final entry in componentsDir.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) {
        continue;
      }
      final decoded = jsonDecode(await entry.readAsString());
      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      final componentId = decoded['id']?.toString();
      if (componentId == null || componentId.isEmpty) {
        continue;
      }
      final registryRoot = decoded['registryRoot']?.toString() ?? '';
      final manifestNamespace = decoded['namespace']?.toString();
      final resolvedNamespace =
          manifestNamespace == null || manifestNamespace.isEmpty
              ? namespace
              : manifestNamespace;
      final files = _legacyInstalledFiles(
        _stringList(decoded['files']),
        installPath: installPath,
      );
      lock = lock
          .upsertRegistry(
            ShadcnLockRegistry(
              namespace: resolvedNamespace,
              registryRoot: registryRoot,
              sourceRoot: registryRoot,
              sourceManifestHash: '',
            ),
          )
          .upsertComponent(
            ShadcnLockComponent(
              namespace: resolvedNamespace,
              componentId: componentId,
              qualifiedId: '@$resolvedNamespace/$componentId',
              version: decoded['version']?.toString(),
              registryRoot: registryRoot,
              sourceManifestHash: '',
              installedFiles: files,
              dependencies: const {},
              postInstall: const [],
              localeKeys: const [],
            ),
          );
    }
    return lock;
  }

  Future<void> save(ShadcnLock lock) async {
    final payload = const JsonEncoder.withIndent('  ').convert(lock.toJson());
    await file.writeAsString('$payload\n', flush: true);
  }
}

class ShadcnLock {
  final int lockfileVersion;
  final Map<String, ShadcnLockRegistry> registries;
  final List<ShadcnLockComponent> components;

  const ShadcnLock({
    this.lockfileVersion = 1,
    this.registries = const {},
    this.components = const [],
  });

  factory ShadcnLock.fromJson(Map<String, dynamic> json) {
    final registriesJson = json['registries'];
    final componentsJson = json['components'];
    return ShadcnLock(
      lockfileVersion: (json['lockfileVersion'] as num?)?.toInt() ?? 1,
      registries: registriesJson is Map<String, dynamic>
          ? registriesJson.map(
              (key, value) => MapEntry(
                key,
                ShadcnLockRegistry.fromJson(value as Map<String, dynamic>),
              ),
            )
          : const {},
      components: componentsJson is List
          ? componentsJson
              .whereType<Map<String, dynamic>>()
              .map(ShadcnLockComponent.fromJson)
              .toList()
          : const [],
    );
  }

  ShadcnLock upsertRegistry(ShadcnLockRegistry registry) {
    final next = Map<String, ShadcnLockRegistry>.from(registries);
    next[registry.namespace] = registry;
    return copyWith(registries: next);
  }

  ShadcnLock upsertComponent(ShadcnLockComponent component) {
    final next = components
        .where(
          (existing) =>
              existing.namespace != component.namespace ||
              existing.componentId != component.componentId,
        )
        .toList()
      ..add(component)
      ..sort((a, b) => a.qualifiedId.compareTo(b.qualifiedId));
    return copyWith(components: next);
  }

  ShadcnLock removeComponent({
    required String namespace,
    required String componentId,
  }) {
    return copyWith(
      components: components
          .where(
            (component) =>
                component.namespace != namespace ||
                component.componentId != componentId,
          )
          .toList(),
    );
  }

  ShadcnLockComponent? componentFor({
    required String namespace,
    required String componentId,
  }) {
    for (final component in components) {
      if (component.namespace == namespace &&
          component.componentId == componentId) {
        return component;
      }
    }
    return null;
  }

  ShadcnLock copyWith({
    int? lockfileVersion,
    Map<String, ShadcnLockRegistry>? registries,
    List<ShadcnLockComponent>? components,
  }) {
    return ShadcnLock(
      lockfileVersion: lockfileVersion ?? this.lockfileVersion,
      registries: registries ?? this.registries,
      components: components ?? this.components,
    );
  }

  Map<String, dynamic> toJson() {
    final sortedRegistries = Map.fromEntries(
      registries.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    final sortedComponents = components.toList()
      ..sort((a, b) => a.qualifiedId.compareTo(b.qualifiedId));
    return {
      'lockfileVersion': lockfileVersion,
      'registries': sortedRegistries.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'components':
          sortedComponents.map((component) => component.toJson()).toList(),
    };
  }
}

class ShadcnLockRegistry {
  final String namespace;
  final String registryRoot;
  final String sourceRoot;
  final String sourceManifestHash;

  const ShadcnLockRegistry({
    required this.namespace,
    required this.registryRoot,
    required this.sourceRoot,
    required this.sourceManifestHash,
  });

  factory ShadcnLockRegistry.fromJson(Map<String, dynamic> json) {
    return ShadcnLockRegistry(
      namespace: json['namespace']?.toString() ?? '',
      registryRoot: json['registryRoot']?.toString() ?? '',
      sourceRoot: json['sourceRoot']?.toString() ?? '',
      sourceManifestHash: json['sourceManifestHash']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'namespace': namespace,
      'registryRoot': registryRoot,
      'sourceRoot': sourceRoot,
      'sourceManifestHash': sourceManifestHash,
    };
  }
}

class ShadcnLockComponent {
  final String namespace;
  final String componentId;
  final String qualifiedId;
  final String? version;
  final String registryRoot;
  final String sourceManifestHash;
  final List<String> installedFiles;
  final Map<String, dynamic> dependencies;
  final List<String> postInstall;
  final List<String> localeKeys;

  const ShadcnLockComponent({
    required this.namespace,
    required this.componentId,
    required this.qualifiedId,
    required this.version,
    required this.registryRoot,
    required this.sourceManifestHash,
    required this.installedFiles,
    required this.dependencies,
    required this.postInstall,
    this.localeKeys = const [],
  });

  factory ShadcnLockComponent.fromJson(Map<String, dynamic> json) {
    return ShadcnLockComponent(
      namespace: json['namespace']?.toString() ?? '',
      componentId: json['componentId']?.toString() ?? '',
      qualifiedId: json['qualifiedId']?.toString() ?? '',
      version: json['version']?.toString(),
      registryRoot: json['registryRoot']?.toString() ?? '',
      sourceManifestHash: json['sourceManifestHash']?.toString() ?? '',
      installedFiles: _stringList(json['installedFiles']),
      dependencies: json['dependencies'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['dependencies'] as Map)
          : const {},
      postInstall: _stringList(json['postInstall']),
      localeKeys: _stringList(json['localeKeys']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'namespace': namespace,
      'componentId': componentId,
      'qualifiedId': qualifiedId,
      if (version != null) 'version': version,
      'registryRoot': registryRoot,
      'sourceManifestHash': sourceManifestHash,
      'installedFiles': installedFiles.toList()..sort(),
      'dependencies': Map.fromEntries(
        dependencies.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
      'postInstall': postInstall,
      'localeKeys': localeKeys.toList()..sort(),
    };
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map((entry) => entry.toString()).toList();
}

List<String> _legacyInstalledFiles(
  List<String> manifestFiles, {
  required String installPath,
}) {
  final files = <String>[];
  for (final file in manifestFiles) {
    final normalized = file.replaceAll('\\', '/');
    const registryPrefix = 'registry/';
    if (normalized.startsWith(registryPrefix)) {
      files.add(
          p.join(installPath, normalized.substring(registryPrefix.length)));
      continue;
    }
    files.add(normalized);
  }
  files.sort();
  return files;
}
