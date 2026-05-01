import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/infrastructure/resolver/v1/project_path_guard.dart';
import 'package:flutter_shadcn_cli/src/state/registry_state_entry.dart';
import 'package:path/path.dart' as p;

class ShadcnStateLoadException implements Exception {
  final String path;
  final Object cause;

  const ShadcnStateLoadException({
    required this.path,
    required this.cause,
  });

  @override
  String toString() => 'Failed to load state JSON at $path: $cause';
}

class ShadcnState {
  static const String fallbackDefaultNamespace = 'shadcn';

  final String? installPath;
  final String? sharedPath;
  final String? themeId;
  final List<String>? managedDependencies;
  final Map<String, RegistryStateEntry>? registries;

  const ShadcnState({
    this.installPath,
    this.sharedPath,
    this.themeId,
    this.managedDependencies,
    this.registries,
  });

  factory ShadcnState.fromJson(Map<String, dynamic> json) {
    final parsedRegistries = _parseRegistries(json['registries']);
    final defaultNamespace = _resolveDefaultNamespace(
      requestedDefaultNamespace: json['defaultNamespace'] as String?,
      registries: parsedRegistries,
    );
    final activeRegistry = parsedRegistries?[defaultNamespace];

    return ShadcnState(
      installPath:
          json['installPath'] as String? ?? activeRegistry?.installPath,
      sharedPath: json['sharedPath'] as String? ?? activeRegistry?.sharedPath,
      themeId: json['themeId'] as String? ?? activeRegistry?.themeId,
      managedDependencies: (json['managedDependencies'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      registries: parsedRegistries,
    );
  }

  Map<String, dynamic> toJson() {
    final defaultNamespace = _resolveDefaultNamespace(
      requestedDefaultNamespace: null,
      registries: registries,
    );
    final active = registries?[defaultNamespace];
    return {
      'installPath': installPath ?? active?.installPath,
      'sharedPath': sharedPath ?? active?.sharedPath,
      'themeId': themeId ?? active?.themeId,
      'managedDependencies': managedDependencies,
      'defaultNamespace': defaultNamespace,
      'registries': registries?.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
    };
  }

  static File stateFile(String targetDir) {
    return File(p.join(targetDir, '.shadcn', 'state.json'));
  }

  static Future<ShadcnState> load(
    String targetDir, {
    String defaultNamespace = fallbackDefaultNamespace,
  }) async {
    final file = stateFile(targetDir);
    if (!await file.exists()) {
      return const ShadcnState();
    }
    final content = await file.readAsString();
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('state root must be a JSON object');
      }
      final raw = decoded;
      final normalized = _normalizeStateShape(
        raw,
        defaultNamespace: defaultNamespace,
      );
      final state = ShadcnState.fromJson(normalized);
      if (_needsStateNormalization(raw)) {
        await save(targetDir, state);
      }
      return state;
    } catch (error) {
      throw ShadcnStateLoadException(path: file.path, cause: error);
    }
  }

  static Future<void> save(String targetDir, ShadcnState state) async {
    final file = File(
      ProjectPathGuard.resolveSafeWritePath(
        projectRoot: targetDir,
        destinationRelativePath: p.join('.shadcn', 'state.json'),
      ),
    );
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(state.toJson()));
  }

  RegistryStateEntry? registryState([String? namespace]) {
    final key = namespace?.trim().isNotEmpty == true
        ? namespace!.trim()
        : _resolveDefaultNamespace(
            requestedDefaultNamespace: null,
            registries: registries,
          );
    return registries?[key];
  }

  ShadcnState withRegistryState(String namespace, RegistryStateEntry entry) {
    final next = Map<String, RegistryStateEntry>.from(registries ?? const {});
    next[namespace] = entry;
    return ShadcnState(
      installPath: installPath ?? entry.installPath,
      sharedPath: sharedPath ?? entry.sharedPath,
      themeId: themeId ?? entry.themeId,
      managedDependencies: managedDependencies,
      registries: next,
    );
  }

  static Map<String, RegistryStateEntry>? _parseRegistries(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final parsed = <String, RegistryStateEntry>{};
    raw.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        parsed[key.toString()] = RegistryStateEntry.fromJson(value);
        return;
      }
      if (value is Map) {
        parsed[key.toString()] = RegistryStateEntry.fromJson(
          value.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    });
    return parsed.isEmpty ? null : parsed;
  }

  static String _resolveDefaultNamespace({
    required String? requestedDefaultNamespace,
    required Map<String, RegistryStateEntry>? registries,
  }) {
    final trimmed = requestedDefaultNamespace?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    if (registries != null && registries.isNotEmpty) {
      return registries.keys.first;
    }
    return fallbackDefaultNamespace;
  }

  static bool _needsStateNormalization(Map<String, dynamic> raw) {
    if (raw['registries'] is Map) {
      return false;
    }
    return raw.containsKey('installPath') ||
        raw.containsKey('sharedPath') ||
        raw.containsKey('themeId');
  }

  static Map<String, dynamic> _normalizeStateShape(
    Map<String, dynamic> raw, {
    required String defaultNamespace,
  }) {
    if (!_needsStateNormalization(raw)) {
      return raw;
    }
    final namespace =
        (raw['defaultNamespace'] as String?)?.trim().isNotEmpty == true
            ? (raw['defaultNamespace'] as String).trim()
            : defaultNamespace;

    final normalized = Map<String, dynamic>.from(raw);
    normalized['defaultNamespace'] = namespace;
    normalized['registries'] = {
      namespace: {
        'installPath': raw['installPath'],
        'sharedPath': raw['sharedPath'],
        'themeId': raw['themeId'],
      },
    };
    return normalized;
  }
}
