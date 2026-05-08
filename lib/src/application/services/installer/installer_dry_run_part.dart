part of 'installer.dart';

extension InstallerDryRunPart on Installer {
  Future<DryRunPlan> buildDryRunPlan(
    List<String> componentIds, {
    bool includeDependencies = true,
  }) async {
    await _ensureConfigLoaded();
    final graphService = RegistryDependencyGraph(registry);
    await graphService.validateComponentInstall(
      componentIds.where((id) => registry.getComponent(id) != null),
      includeDependencies: includeDependencies,
      allowMissing: true,
    );
    final requested = componentIds.toList();
    final missing = <String>[];
    final resolved = <String, Component>{};
    final dependencyGraph = await graphService.componentDependencyGraph(
      componentIds.where((id) => registry.getComponent(id) != null),
      includeDependencies: includeDependencies,
      allowMissing: true,
    );

    void visit(Component component, Set<String> stack) {
      if (resolved.containsKey(component.id)) {
        return;
      }
      if (stack.contains(component.id)) {
        return;
      }
      stack.add(component.id);
      resolved[component.id] = component;
      if (includeDependencies) {
        for (final depId in component.dependsOn) {
          final dep = registry.getComponent(depId);
          if (dep == null) {
            missing.add(depId);
          } else {
            visit(dep, stack);
          }
        }
      }
      stack.remove(component.id);
    }

    for (final id in componentIds) {
      final component = registry.getComponent(id);
      if (component == null) {
        missing.add(id);
        continue;
      }
      visit(component, <String>{});
    }

    final shared = <String>{};
    final pubspecDependencies = <String, dynamic>{};
    final assets = <String>{};
    final fontsByFamily = <String, FontEntry>{};
    final postInstall = <String>{};
    final fileDependencies = <String>{};
    final platformChanges = <String, Set<String>>{};
    final componentFiles = <String, List<Map<String, String>>>{};
    final manifestPreview = <String, Map<String, dynamic>>{};

    for (final component in resolved.values) {
      for (final sharedId in component.shared) {
        shared.add(_normalizeSharedId(sharedId));
      }
      final deps = component.pubspec['dependencies'] as Map<String, dynamic>?;
      deps?.forEach((key, value) {
        if (value != null && !pubspecDependencies.containsKey(key)) {
          pubspecDependencies[key] = value;
        }
      });
      assets.addAll(component.assets);
      for (final font in component.fonts) {
        fontsByFamily.putIfAbsent(font.family, () => font);
      }
      postInstall.addAll(component.postInstall);

      for (final file in component.files) {
        for (final dep in file.dependsOn) {
          final label = dep.optional ? '${dep.source} (optional)' : dep.source;
          fileDependencies.add(label);
        }
      }

      component.platform.forEach((platform, entry) {
        final sections = <String>{};
        if (entry.permissions.isNotEmpty) {
          sections.add('permissions');
        }
        if (entry.infoPlist.isNotEmpty) {
          sections.add('infoPlist');
        }
        if (entry.entitlements.isNotEmpty) {
          sections.add('entitlements');
        }
        if (entry.podfile.isNotEmpty) {
          sections.add('podfile');
        }
        if (entry.gradle.isNotEmpty) {
          sections.add('gradle');
        }
        if (entry.config.isNotEmpty) {
          sections.add('config');
        }
        if (entry.notes.isNotEmpty) {
          sections.add('notes');
        }
        if (sections.isNotEmpty) {
          platformChanges
              .putIfAbsent(platform, () => <String>{})
              .addAll(sections);
        }
      });

      final fileEntries = <Map<String, String>>[];
      for (final file in component.files) {
        final destination = _resolveComponentDestination(component, file);
        fileEntries.add({'source': file.source, 'destination': destination});
      }
      componentFiles[component.id] = fileEntries;
      manifestPreview[component.id] = {
        'id': component.id,
        'name': component.name,
        'version': component.version,
        'tags': component.tags,
        'shared': component.shared.toList()..sort(),
        'dependsOn': component.dependsOn.toList()..sort(),
        'files': component.files.map((f) => f.source).toList()..sort(),
        'registryRoot': registry.registryRoot.root,
      };
    }

    final components = resolved.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    return DryRunPlan(
      requested: requested,
      missing: missing.toSet().toList()..sort(),
      components: components,
      dependencyGraph: dependencyGraph,
      shared: shared.toList()..sort(),
      pubspecDependencies: pubspecDependencies,
      assets: assets.toList()..sort(),
      fonts: fontsByFamily.values.toList()
        ..sort((a, b) => a.family.compareTo(b.family)),
      postInstall: postInstall.toList()..sort(),
      fileDependencies: fileDependencies.toList()..sort(),
      platformChanges: platformChanges,
      componentFiles: componentFiles,
      manifestPreview: manifestPreview,
    );
  }

  void printDryRunPlan(DryRunPlan plan) {
    logger.header('Dry Run Preview');

    void section(String title, List<String> lines) {
      if (lines.isEmpty) {
        return;
      }
      final countLabel = lines.length == 1 ? '1 item' : '${lines.length} items';
      print('\n$title ($countLabel)');
      print('─' * (title.length + countLabel.length + 3));
      for (final line in lines) {
        print('  • $line');
      }
    }

    section('Requested components', plan.requested);
    section('Missing components', plan.missing);

    if (plan.components.isNotEmpty) {
      final componentLines = <String>[];
      for (final component in plan.components) {
        final deps = plan.dependencyGraph[component.id] ?? const [];
        if (deps.isEmpty) {
          componentLines.add(component.id);
        } else {
          componentLines.add(
            '${component.id}  ↳ dependsOn: ${deps.join(', ')}',
          );
        }
      }
      section('Components to install', componentLines);
    }

    section('Shared modules', plan.shared);

    if (plan.pubspecDependencies.isNotEmpty) {
      final keys = plan.pubspecDependencies.keys.toList()..sort();
      final dependencyLines = <String>[];
      for (final key in keys) {
        dependencyLines.add('$key: ${plan.pubspecDependencies[key]}');
      }
      section('Pubspec dependencies', dependencyLines);
    }

    section('Assets', plan.assets);

    if (plan.fonts.isNotEmpty) {
      final fontLines = <String>[];
      for (final font in plan.fonts) {
        fontLines.add(font.family);
        for (final fontAsset in font.fonts) {
          final weight =
              fontAsset.weight != null ? ' weight ${fontAsset.weight}' : '';
          final style = fontAsset.style != null ? ' ${fontAsset.style}' : '';
          fontLines.add('  - ${fontAsset.asset}$weight$style');
        }
      }
      section('Fonts', fontLines);
    }

    section('File dependencies', plan.fileDependencies);

    if (plan.componentFiles.isNotEmpty) {
      final fileLines = <String>[];
      final ids = plan.componentFiles.keys.toList()..sort();
      for (final id in ids) {
        final entries = plan.componentFiles[id] ?? const [];
        for (final entry in entries) {
          fileLines.add('$id: ${entry['source']} -> ${entry['destination']}');
        }
      }
      section('File destinations', fileLines);
    }

    if (plan.manifestPreview.isNotEmpty) {
      final previewLines = <String>[];
      final ids = plan.manifestPreview.keys.toList()..sort();
      for (final id in ids) {
        final entry = plan.manifestPreview[id] ?? const {};
        final version = entry['version'] ?? 'unknown';
        final tags = (entry['tags'] as List?)?.join(', ') ?? '';
        previewLines.add('$id: version=$version tags=[$tags]');
      }
      section('Manifest preview', previewLines);
    }

    if (plan.platformChanges.isNotEmpty) {
      final platformLines = <String>[];
      final platforms = plan.platformChanges.keys.toList()..sort();
      for (final platform in platforms) {
        final sections = plan.platformChanges[platform]!.toList()..sort();
        platformLines.add('$platform: ${sections.join(', ')}');
      }
      section('Platform changes', platformLines);
    }

    section('Post-install notes', plan.postInstall);
  }
}
