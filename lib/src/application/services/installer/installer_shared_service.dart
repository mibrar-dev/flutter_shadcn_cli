import 'dart:convert';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer_registry_file_owner.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;

typedef InstallerSharedFileInstaller = Future<void> Function(
  RegistryFile file,
  List<RegistryFile> availableFiles, {
  String? sharedId,
});

class InstallerSharedService {
  static final RegExp _importDirectiveRegex = RegExp(
    r'''^\s*(import|export|part)\s+['"]([^'"]+)['"]''',
  );
  static final RegExp _partOfDirectiveRegex = RegExp(r'^\s*part\s+of\b');

  final Registry registry;
  final CliLogger logger;

  final Set<String> _installingSharedIds = {};
  final Set<String> _installedSharedCache = {};
  final Map<String, Set<String>> _sharedDependencyCache = {};
  Map<String, InstallerRegistryFileOwner>? _registryFileIndex;

  InstallerSharedService({required this.registry, required this.logger});

  Future<void> installShared(
    String id, {
    required Future<void> Function() ensureConfigLoaded,
    required Future<void> Function(String id) installComponent,
    required InstallerSharedFileInstaller installFileWithDependencies,
  }) async {
    await ensureConfigLoaded();
    final resolvedId = normalizeSharedId(id);
    final sharedItem = registry.getSharedItem(resolvedId);
    if (sharedItem == null) {
      final fallbackComponent = registry.getComponent(resolvedId);
      if (fallbackComponent != null) {
        await installComponent(resolvedId);
        return;
      }
      logger.warn('Shared item "$id" not found');
      return;
    }

    if (_installedSharedCache.contains(resolvedId)) {
      return;
    }
    if (_installingSharedIds.contains(resolvedId)) {
      return;
    }

    _installingSharedIds.add(resolvedId);
    try {
      final sharedDeps = await loadSharedDependencies(resolvedId);
      for (final depId in sharedDeps) {
        await installShared(
          depId,
          ensureConfigLoaded: ensureConfigLoaded,
          installComponent: installComponent,
          installFileWithDependencies: installFileWithDependencies,
        );
      }
      for (final file in sharedItem.files) {
        await installFileWithDependencies(
          file,
          sharedItem.files,
          sharedId: sharedItem.id,
        );
      }

      _installedSharedCache.add(resolvedId);
    } finally {
      _installingSharedIds.remove(resolvedId);
    }
  }

  List<String> coreSharedIdsForInit() {
    final ids = <String>[
      'theme',
      'util',
      'color_extensions',
      'form_control',
      'form_value_supplier',
    ];
    if (registry.getSharedItem('color_scheme') != null) {
      ids.add('color_scheme');
    }
    return ids;
  }

  String normalizeSharedId(String id) {
    switch (id) {
      case 'utils':
        return 'util';
      default:
        return id;
    }
  }

  Future<Set<String>> resolveSharedDependencyClosure(
    Set<String> seedIds,
  ) async {
    final resolved = <String>{};
    final pending = <String>[];
    for (final id in seedIds) {
      pending.add(normalizeSharedId(id));
    }
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!resolved.add(id)) {
        continue;
      }
      final deps = await loadSharedDependencies(id);
      for (final dep in deps) {
        final normalized = normalizeSharedId(dep);
        if (!resolved.contains(normalized)) {
          pending.add(normalized);
        }
      }
    }
    return resolved;
  }

  Future<Set<String>> loadSharedDependencies(String sharedId) async {
    final cached = _sharedDependencyCache[sharedId];
    if (cached != null) {
      return cached;
    }

    final sharedItem = registry.getSharedItem(sharedId);
    if (sharedItem == null) {
      _sharedDependencyCache[sharedId] = {};
      return {};
    }

    final deps = <String>{};
    for (final file in sharedItem.files) {
      if (!file.source.endsWith('.dart')) {
        continue;
      }
      try {
        final bytes = await registry.readSourceBytes(file.source);
        final content = utf8.decode(bytes);
        final dir = p.posix.dirname(normalizeRegistryPath(file.source));
        for (final line in content.split('\n')) {
          if (_partOfDirectiveRegex.hasMatch(line)) {
            continue;
          }
          final match = _importDirectiveRegex.firstMatch(line);
          if (match == null) {
            continue;
          }
          final importPath = match.group(2);
          if (importPath == null || !_isRelativeImport(importPath)) {
            continue;
          }
          final resolved = p.posix.normalize(p.posix.join(dir, importPath));
          final owner = lookupRegistryFileOwner(resolved);
          if (owner != null && owner.isShared && owner.id != sharedId) {
            deps.add(owner.id);
          }
        }
      } catch (_) {
        continue;
      }
    }

    _sharedDependencyCache[sharedId] = deps;
    return deps;
  }

  InstallerRegistryFileOwner? lookupRegistryFileOwner(String source) {
    final normalized = normalizeRegistryPath(source);
    return _buildRegistryFileIndex()[normalized];
  }

  String normalizeRegistryPath(String source) {
    final normalized = source.replaceAll('\\', '/');
    return p.posix.normalize(normalized);
  }

  bool _isRelativeImport(String path) {
    final uri = Uri.tryParse(path);
    if (uri != null && uri.hasScheme) {
      return false;
    }
    return !path.startsWith('/');
  }

  Map<String, InstallerRegistryFileOwner> _buildRegistryFileIndex() {
    final cached = _registryFileIndex;
    if (cached != null) {
      return cached;
    }
    final index = <String, InstallerRegistryFileOwner>{};
    for (final sharedItem in registry.shared) {
      for (final file in sharedItem.files) {
        final normalized = normalizeRegistryPath(file.source);
        index[normalized] = InstallerRegistryFileOwner.shared(
          sharedItem.id,
          file,
        );
      }
    }
    for (final component in registry.components) {
      for (final file in component.files) {
        final normalized = normalizeRegistryPath(file.source);
        index[normalized] = InstallerRegistryFileOwner.component(
          component.id,
          file,
        );
      }
    }
    _registryFileIndex = index;
    return index;
  }
}
