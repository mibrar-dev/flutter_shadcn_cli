part of 'multi_registry_manager.dart';

extension MultiRegistryAssetsPart on MultiRegistryManager {
  Future<bool> runInlineAssets({
    required String namespace,
    required bool installIcons,
    required bool installTypography,
    required bool installAll,
  }) async {
    final projectRoot = findProjectRootFrom(targetDir);
    var config = await ShadcnConfig.load(projectRoot);
    late final RegistryDirectoryEntry entry;
    try {
      final directory = await _loadDirectory();
      entry = directory.registries.firstWhere(
        (item) => item.namespace == namespace,
      );
    } catch (_) {
      return false;
    }
    if (!entry.hasInlineInit) {
      return false;
    }

    final selectedActions = _selectInlineAssetActions(
      entry: entry,
      installIcons: installIcons,
      installTypography: installTypography,
      installAll: installAll,
    );
    if (selectedActions.isEmpty) {
      return false;
    }

    final nextConfig = await _upsertConfigFromDirectory(config, entry);
    final configured = nextConfig.registryConfig(namespace);
    final overrideBaseUrl = _inlineActionBaseUrl(
      entry: entry,
      configEntry: configured,
    );
    final baseUrl =
        overrideBaseUrl.isNotEmpty ? overrideBaseUrl : entry.baseUrl;
    final result = await initActionEngine.executeActions(
      projectRoot: projectRoot,
      baseUrl: baseUrl,
      actions: selectedActions,
      logger: logger,
    );
    await ShadcnConfig.save(projectRoot, nextConfig);
    final category = _inlineAssetCategory(
      installIcons: installIcons,
      installTypography: installTypography,
      installAll: installAll,
    );
    await _recordInlineExecution(
      projectRoot: projectRoot,
      namespace: namespace,
      category: category,
      record: result.record,
    );
    return true;
  }

  Future<bool> rollbackInlineAssets({
    required String namespace,
    required bool removeIcons,
    required bool removeTypography,
    required bool removeAll,
  }) async {
    final projectRoot = findProjectRootFrom(targetDir);
    final journal = await InlineActionJournal.load(projectRoot);
    if (removeAll) {
      final snapshot = journal.takeAll(namespace);
      if (snapshot.entries.isEmpty) {
        return false;
      }
      final entries = snapshot.entries.toList().reversed.toList();
      for (final entry in entries) {
        await initActionEngine.rollbackRecordedChanges(
          projectRoot: projectRoot,
          record: entry.record,
          logger: logger,
        );
      }
      await snapshot.journal.save(projectRoot);
      return true;
    }

    final desired = <String>{};
    if (removeIcons) {
      desired.add('assets:icons');
      desired.add('assets:all');
    }
    if (removeTypography) {
      desired.add('assets:typography');
      desired.add('assets:all');
    }
    if (desired.isEmpty) {
      return false;
    }
    final snapshot = journal.takeLatest(
      namespace,
      where: (entry) => desired.contains(entry.category),
    );
    if (snapshot.entry == null) {
      return false;
    }
    await initActionEngine.rollbackRecordedChanges(
      projectRoot: projectRoot,
      record: snapshot.entry!.record,
      logger: logger,
    );
    await snapshot.journal.save(projectRoot);
    return true;
  }

  List<Map<String, dynamic>> _selectInlineAssetActions({
    required RegistryDirectoryEntry entry,
    required bool installIcons,
    required bool installTypography,
    required bool installAll,
  }) {
    final init = entry.init;
    if (init == null || !entry.hasInlineInit) {
      return const [];
    }
    final actionList = (init['actions'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
    if (actionList.isEmpty) {
      return const [];
    }
    if (installAll || (installIcons && installTypography)) {
      return actionList.where(_matchesAnyAssetScope).toList();
    }
    return actionList.where((action) {
      if (installIcons && _matchesIconScope(action)) {
        return true;
      }
      if (installTypography && _matchesTypographyScope(action)) {
        return true;
      }
      return false;
    }).toList();
  }

  bool _matchesAnyAssetScope(Map<String, dynamic> action) {
    return _matchesIconScope(action) || _matchesTypographyScope(action);
  }

  bool _matchesIconScope(Map<String, dynamic> action) {
    final scopes = _extractActionScopes(action);
    if (scopes.isNotEmpty) {
      if (scopes.contains('all') || scopes.contains('assets')) {
        return true;
      }
      return scopes.contains('icons') ||
          scopes.contains('icon') ||
          scopes.contains('icon_fonts');
    }
    final text = _actionTextBlob(action);
    return text.contains('icon') ||
        text.contains('lucide') ||
        text.contains('radix') ||
        text.contains('bootstrap');
  }

  bool _matchesTypographyScope(Map<String, dynamic> action) {
    final scopes = _extractActionScopes(action);
    if (scopes.isNotEmpty) {
      if (scopes.contains('all') || scopes.contains('assets')) {
        return true;
      }
      return scopes.contains('typography') ||
          scopes.contains('fonts') ||
          scopes.contains('font') ||
          scopes.contains('typography_fonts');
    }
    final text = _actionTextBlob(action);
    return text.contains('typography') ||
        text.contains('font') ||
        text.contains('geist');
  }

  Set<String> _extractActionScopes(Map<String, dynamic> action) {
    final scopeValues = <String>{};
    for (final key in const [
      'scope',
      'scopes',
      'group',
      'groups',
      'profile',
      'profiles',
      'tag',
      'tags',
    ]) {
      final value = action[key];
      if (value is String) {
        scopeValues.addAll(
          value
              .toLowerCase()
              .split(RegExp(r'[,/ ]+'))
              .map((part) => part.trim())
              .where((part) => part.isNotEmpty),
        );
      } else if (value is List) {
        for (final item in value) {
          final token = item.toString().trim().toLowerCase();
          if (token.isNotEmpty) {
            scopeValues.add(token);
          }
        }
      }
    }
    return scopeValues;
  }

  String _actionTextBlob(Map<String, dynamic> action) {
    final values = <String>[];
    void walk(dynamic value) {
      if (value == null) {
        return;
      }
      if (value is String) {
        values.add(value.toLowerCase());
        return;
      }
      if (value is List) {
        for (final item in value) {
          walk(item);
        }
        return;
      }
      if (value is Map) {
        value.forEach((key, item) {
          values.add(key.toString().toLowerCase());
          walk(item);
        });
      }
    }

    walk(action);
    return values.join(' ');
  }
}
