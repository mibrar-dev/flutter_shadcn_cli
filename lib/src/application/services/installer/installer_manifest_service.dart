import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/infrastructure/resolver/v1/project_path_guard.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;

class InstallerManifestService {
  InstallerManifestService({
    required this.targetDir,
    required this.registry,
    this.registryNamespace,
    this.registryBaseUrlOverride,
  });

  final String targetDir;
  final Registry registry;
  final String? registryNamespace;
  final String? registryBaseUrlOverride;

  Future<void> updateAggregateManifest({
    required String installPath,
    required String sharedPath,
    required Set<String> installedComponentIds,
    required Map<String, dynamic> managedDependencies,
  }) async {
    final manifestFile = File(
      _resolveProjectPath(p.join(installPath, 'components.json')),
    );
    if (installedComponentIds.isEmpty) {
      if (await manifestFile.exists()) {
        await manifestFile.delete();
      }
      await clearComponentManifests();
      return;
    }

    final installedList = installedComponentIds.toList()..sort();
    final componentMeta = <String, dynamic>{};
    for (final id in installedList) {
      final component = registry.getComponent(id);
      if (component == null) {
        continue;
      }
      componentMeta[id] = {
        'version': component.version,
        'tags': component.tags,
      };
    }
    final payload = {
      'schemaVersion': 1,
      'installPath': installPath,
      'sharedPath': sharedPath,
      'installed': installedList,
      'managedDependencies': managedDependencies.keys.toList()..sort(),
      'componentMeta': componentMeta,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    if (!await manifestFile.parent.exists()) {
      await manifestFile.parent.create(recursive: true);
    }
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Directory componentManifestDirectory() {
    return Directory(_resolveProjectPath(p.join('.shadcn', 'components')));
  }

  File componentManifestFile(String componentId) {
    return File(
      _resolveProjectPath(p.join('.shadcn', 'components', '$componentId.json')),
    );
  }

  Future<void> writeComponentManifest(
    Component component, {
    List<Map<String, dynamic>> localeResourcesInstalled = const [],
  }) async {
    final dir = componentManifestDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = componentManifestFile(component.id);
    final payload = {
      'schemaVersion': 1,
      'id': component.id,
      'name': component.name,
      'version': component.version,
      'tags': component.tags,
      'installedAt': await _existingInstalledAt(file) ??
          DateTime.now().toUtc().toIso8601String(),
      'shared': component.shared.toList()..sort(),
      'dependsOn': component.dependsOn.toList()..sort(),
      'files': component.files.map((file) => file.source).toList()..sort(),
      if (localeResourcesInstalled.isNotEmpty)
        'locale': {
          'resourcesInstalled': localeResourcesInstalled,
          'selectionSource': 'registryDefault',
        },
      if (registryNamespace != null) 'registryNamespace': registryNamespace,
      if (registryBaseUrlOverride != null)
        'registrySource': registryBaseUrlOverride,
      'manifestSource': 'componentsJson',
      'registryRoot': registry.registryRoot.root,
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<void> removeComponentManifest(String componentId) async {
    final file = componentManifestFile(componentId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> clearComponentManifests() async {
    final dir = componentManifestDirectory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<String?> _existingInstalledAt(File file) async {
    if (!await file.exists()) {
      return null;
    }
    try {
      final content = await file.readAsString();
      final data = jsonDecode(content);
      if (data is Map<String, dynamic>) {
        final value = data['installedAt']?.toString();
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }
    } catch (_) {}
    return null;
  }

  String _resolveProjectPath(String relativePath) {
    return ProjectPathGuard.resolveSafeWritePath(
      projectRoot: targetDir,
      destinationRelativePath: relativePath,
    );
  }
}
