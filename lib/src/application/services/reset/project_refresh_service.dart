import 'dart:io';

import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/init_action_engine.dart';
import 'package:flutter_shadcn_cli/src/inline_action_journal.dart';
import 'package:flutter_shadcn_cli/src/registry_directory.dart';
import 'package:flutter_shadcn_cli/src/resolver_v1.dart';
import 'package:flutter_shadcn_cli/src/state.dart';
import 'package:path/path.dart' as p;

typedef ProjectRefreshActionExecutor = Future<InitExecutionResult> Function({
  required String projectRoot,
  required String baseUrl,
  required List<Map<String, dynamic>> actions,
  InitOptionalActionDecider? optionalActionDecider,
  InitActionGroupSelector? groupSelector,
});

class ProjectRefreshResult {
  final String namespace;
  final List<String> missingFiles;
  final InitExecutionResult executionResult;

  const ProjectRefreshResult({
    required this.namespace,
    required this.missingFiles,
    required this.executionResult,
  });
}

class ProjectRefreshService {
  final String projectRoot;
  final ProjectRefreshActionExecutor executeActions;

  ProjectRefreshService({
    required this.projectRoot,
    required this.executeActions,
  });

  Future<ProjectRefreshResult> refresh({
    required RegistryDirectoryEntry registry,
    String? namespace,
    InitOptionalActionDecider? optionalActionDecider,
    InitActionGroupSelector? groupSelector,
  }) async {
    final normalizedRoot = p.normalize(p.absolute(projectRoot));
    final config = await ShadcnConfig.load(normalizedRoot);
    final state = await ShadcnState.load(
      normalizedRoot,
      defaultNamespace: config.effectiveDefaultNamespace,
    );
    final resolvedNamespace = _resolveNamespace(
      config: config,
      registry: registry,
      namespace: namespace,
    );
    final journal = await InlineActionJournal.load(normalizedRoot);
    final recordedFiles = <String>{
      for (final entry in journal.byNamespace[resolvedNamespace] ?? const [])
        ...entry.record.filesWritten,
    };
    final installPath = _resolveInstallPath(
      config: config,
      state: state,
      namespace: resolvedNamespace,
    );
    final sharedPath = _resolveSharedPath(
      config: config,
      state: state,
      namespace: resolvedNamespace,
    );

    final actions = _normalizeActions(registry);
    final missingFiles = <String>{};
    final refreshActions = <Map<String, dynamic>>[];
    var hasSelectedRepairAction = false;

    for (final action in actions) {
      final type = action['type']?.toString();
      switch (type) {
        case 'copyFiles':
        case 'copyDir':
          final selection = _selectRepairAction(
            projectRoot: normalizedRoot,
            installPath: installPath,
            sharedPath: sharedPath,
            action: action,
            recordedFiles: recordedFiles,
            missingFiles: missingFiles,
          );
          if (selection != null) {
            refreshActions.add(selection);
            hasSelectedRepairAction = true;
          }
          break;
        case 'mergePubspec':
          if (hasSelectedRepairAction) {
            refreshActions.add(action);
          }
          break;
        default:
          break;
      }
    }

    if (refreshActions.isEmpty) {
      return ProjectRefreshResult(
        namespace: resolvedNamespace,
        missingFiles: const [],
        executionResult: const InitExecutionResult(
          dirsCreated: 0,
          filesWritten: 0,
          messages: <String>[],
          record: InitExecutionRecord.empty,
        ),
      );
    }

    final executionResult = await executeActions(
      projectRoot: normalizedRoot,
      baseUrl: _resolveBaseUrl(
        projectRoot: normalizedRoot,
        config: config,
        registry: registry,
        namespace: resolvedNamespace,
      ),
      actions: refreshActions,
      optionalActionDecider: optionalActionDecider,
      groupSelector: groupSelector,
    );

    if (executionResult.record != InitExecutionRecord.empty) {
      await journal
          .append(
            namespace: resolvedNamespace,
            entry: InlineActionJournalEntry(
              category: 'refresh',
              createdAt: DateTime.now().toUtc().toIso8601String(),
              record: executionResult.record,
            ),
          )
          .save(normalizedRoot);
    }

    return ProjectRefreshResult(
      namespace: resolvedNamespace,
      missingFiles: missingFiles.toList()..sort(),
      executionResult: executionResult,
    );
  }

  String _resolveNamespace({
    required ShadcnConfig config,
    required RegistryDirectoryEntry registry,
    required String? namespace,
  }) {
    final requested = namespace?.trim();
    if (requested != null && requested.isNotEmpty) {
      return requested;
    }
    final configured = config.effectiveDefaultNamespace.trim();
    if (configured.isNotEmpty) {
      return configured;
    }
    return registry.namespace;
  }

  String _resolveBaseUrl({
    required String projectRoot,
    required ShadcnConfig config,
    required RegistryDirectoryEntry registry,
    required String namespace,
  }) {
    final configEntry = config.registryConfig(namespace);
    final registryPath = configEntry?.registryPath;
    if (registryPath != null && registryPath.trim().isNotEmpty) {
      return _normalizeLocalRegistryRoot(projectRoot, registryPath);
    }

    if (config.effectiveDefaultNamespace == namespace) {
      final topLevelPath = config.registryPath;
      if (topLevelPath != null && topLevelPath.trim().isNotEmpty) {
        return _normalizeLocalRegistryRoot(projectRoot, topLevelPath);
      }
    }

    return configEntry?.baseUrl ??
        configEntry?.registryUrl ??
        (config.effectiveDefaultNamespace == namespace
            ? config.registryUrl
            : null) ??
        registry.baseUrl;
  }

  String? _resolveInstallPath({
    required ShadcnConfig config,
    required ShadcnState state,
    required String namespace,
  }) {
    return config.registryConfig(namespace)?.installPath ??
        (config.effectiveDefaultNamespace == namespace
            ? config.installPath
            : null) ??
        state.registryState(namespace)?.installPath ??
        state.installPath;
  }

  String? _resolveSharedPath({
    required ShadcnConfig config,
    required ShadcnState state,
    required String namespace,
  }) {
    return config.registryConfig(namespace)?.sharedPath ??
        (config.effectiveDefaultNamespace == namespace
            ? config.sharedPath
            : null) ??
        state.registryState(namespace)?.sharedPath ??
        state.sharedPath;
  }

  List<Map<String, dynamic>> _normalizeActions(
      RegistryDirectoryEntry registry) {
    final init = registry.init;
    if (init == null || !registry.hasInlineInit) {
      return const [];
    }
    return (init['actions'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((entry) => entry.map((key, value) => MapEntry('$key', value)))
        .toList();
  }

  Map<String, dynamic>? _selectRepairAction({
    required String projectRoot,
    required String? installPath,
    required String? sharedPath,
    required Map<String, dynamic> action,
    required Set<String> recordedFiles,
    required Set<String> missingFiles,
  }) {
    final expectedOutputs = _expectedOutputPaths(action).where((relativePath) {
      return _isManagedScaffoldPath(
        relativePath,
        installPath: installPath,
        sharedPath: sharedPath,
      );
    }).toList()
      ..sort();
    if (expectedOutputs.isEmpty) {
      return null;
    }

    final missingExpected = expectedOutputs.where((relativePath) {
      final file = File(p.join(projectRoot, relativePath));
      return !file.existsSync();
    }).toList()
      ..sort();
    if (missingExpected.isEmpty) {
      return null;
    }

    final isOptional = action['optional'] == true;
    if (isOptional) {
      missingFiles.addAll(missingExpected);
      return _cloneActionWithMissingFiles(action, missingExpected);
    }

    final recordedMissing = missingExpected
        .where((relativePath) => recordedFiles.contains(relativePath))
        .toList()
      ..sort();
    final selectedFiles =
        recordedMissing.isNotEmpty ? recordedMissing : missingExpected;
    missingFiles.addAll(selectedFiles);
    return _cloneActionWithMissingFiles(action, selectedFiles);
  }

  List<String> _expectedOutputPaths(Map<String, dynamic> action) {
    final type = action['type']?.toString();
    if (type != 'copyFiles' && type != 'copyDir') {
      return const [];
    }

    final fromRaw = action['from']?.toString();
    final toRaw = action['to']?.toString();
    final usesDirMapping = fromRaw != null && toRaw != null;
    final from =
        usesDirMapping ? ResolverV1.normalizeRelativePath(fromRaw) : null;
    final to = usesDirMapping ? ResolverV1.normalizeRelativePath(toRaw) : null;
    final base = action['base']?.toString();
    final destBase = action['destBase']?.toString();
    final files = _declaredActionFiles(action, usesDirMapping: usesDirMapping);

    final destinations = <String>{};
    for (final file in files) {
      final normalized = ResolverV1.normalizeRelativePath(file);
      final destination = usesDirMapping
          ? InitPathMapper.mapCopyDirDestination(
              filePath: normalized,
              from: from!,
              to: to!,
              base: base,
              destBase: destBase,
            )
          : InitPathMapper.mapCopyFileDestination(
              filePath: normalized,
              base: base,
              destBase: destBase,
            );
      destinations.add(_normalizeRelative(destination));
    }
    return destinations.toList()..sort();
  }

  List<String> _declaredActionFiles(
    Map<String, dynamic> action, {
    required bool usesDirMapping,
  }) {
    final files = <String>{};
    final directFiles = action['files'] as List<dynamic>?;
    if (directFiles != null) {
      for (final file in directFiles) {
        files.add(file.toString());
      }
    }

    final groups = action['groups'] as List<dynamic>?;
    if (groups != null) {
      for (final group in groups.whereType<Map>()) {
        final groupFiles = group['files'] as List<dynamic>?;
        if (groupFiles == null) {
          continue;
        }
        for (final file in groupFiles) {
          final path = file.toString();
          files.add(
            usesDirMapping
                ? p.posix.join(action['from'].toString(), path)
                : path,
          );
        }
      }
    }

    return files.toList()..sort();
  }

  Map<String, dynamic> _cloneActionWithMissingFiles(
    Map<String, dynamic> action,
    List<String> selectedDestinations,
  ) {
    final clone = Map<String, dynamic>.from(action);
    final outputMap = <String, String>{};
    final declaredFiles = _declaredActionFiles(
      action,
      usesDirMapping: action['from']?.toString() != null &&
          action['to']?.toString() != null,
    );
    final expectedOutputs = _expectedOutputPaths(action);
    for (var i = 0;
        i < declaredFiles.length && i < expectedOutputs.length;
        i++) {
      outputMap[expectedOutputs[i]] = declaredFiles[i];
    }

    if (clone['files'] is List) {
      clone['files'] = [
        for (final destination in selectedDestinations)
          outputMap[destination] ?? destination,
      ];
    }

    if (clone['groups'] is List) {
      final from = clone['from']?.toString();
      clone['groups'] = (clone['groups'] as List<dynamic>)
          .whereType<Map>()
          .map((group) {
            final next = group.map((key, value) => MapEntry('$key', value));
            final groupFiles = (next['files'] as List<dynamic>? ?? const [])
                .map((entry) => entry.toString())
                .where((file) {
              final declaredPath =
                  from == null ? file : p.posix.join(from, file);
              final outputs = outputMap.entries
                  .where((entry) =>
                      entry.value == declaredPath || entry.value == file)
                  .map((entry) => entry.key);
              return outputs.any(selectedDestinations.contains);
            }).toList();
            next['files'] = from == null
                ? groupFiles
                : groupFiles
                    .map((file) => p.posix.relative(file, from: from))
                    .toList();
            return next;
          })
          .where((group) => (group['files'] as List<dynamic>).isNotEmpty)
          .toList();
      clone.remove('files');
    }

    return clone;
  }

  String _normalizeRelative(String relativePath) {
    final normalized = p.posix.normalize(relativePath);
    return normalized.startsWith('./') ? normalized.substring(2) : normalized;
  }

  bool _isManagedScaffoldPath(
    String relativePath, {
    required String? installPath,
    required String? sharedPath,
  }) {
    final normalized = _normalizeRelative(relativePath);
    if (normalized == '.shadcn' || normalized.startsWith('.shadcn/')) {
      return true;
    }

    final normalizedInstall = _normalizeNullableRelative(installPath);
    if (normalizedInstall == null) {
      return true;
    }

    if (normalized == normalizedInstall ||
        p.posix.isWithin(normalizedInstall, normalized)) {
      final normalizedShared = _normalizeNullableRelative(sharedPath);
      if (normalizedShared == null) {
        return false;
      }
      return normalized == normalizedShared ||
          p.posix.isWithin(normalizedShared, normalized);
    }

    return true;
  }

  String _normalizeLocalRegistryRoot(String projectRoot, String registryPath) {
    final trimmed = registryPath.trim();
    final absolute = p.isAbsolute(trimmed)
        ? p.normalize(trimmed)
        : p.normalize(p.join(projectRoot, trimmed));
    return p.basename(absolute) == 'registry' ? p.dirname(absolute) : absolute;
  }

  String? _normalizeNullableRelative(String? rawPath) {
    final trimmed = rawPath?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return _normalizeRelative(trimmed);
  }
}
