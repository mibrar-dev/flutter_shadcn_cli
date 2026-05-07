import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry/component.dart';
import 'package:flutter_shadcn_cli/src/registry/components_schema_validator.dart';
import 'package:flutter_shadcn_cli/src/registry/registry_location.dart';
import 'package:flutter_shadcn_cli/src/registry/shared_item.dart';

class RegistrySchemaValidationException implements Exception {
  final List<String> errors;

  const RegistrySchemaValidationException(this.errors);

  @override
  String toString() {
    final details = errors.isEmpty ? '' : ' ${errors.join('; ')}';
    return 'components.json schema validation failed (${errors.length} issues).$details';
  }
}

class Registry {
  final Map<String, dynamic> data;
  final RegistryLocation registryRoot;
  final RegistryLocation sourceRoot;
  List<Component>? _componentsCache;
  Map<String, Component>? _componentLookupCache;

  Registry(this.data, this.registryRoot, this.sourceRoot);

  static Future<Registry> load({
    required RegistryLocation registryRoot,
    required RegistryLocation sourceRoot,
    String? schemaPath,
    String? cachePath,
    String componentsPath = 'components.json',
    String? trustMode,
    String? trustSha256,
    bool skipIntegrity = false,
    bool offline = false,
    CliLogger? logger,
  }) async {
    String content;
    if (offline && registryRoot.isRemote) {
      if (cachePath == null) {
        throw Exception('Offline mode: cache path not available.');
      }
      final cacheFile = File(cachePath);
      if (!await cacheFile.exists()) {
        throw Exception('Offline mode: cached components.json not found.');
      }
      content = await cacheFile.readAsString();
    } else {
      content = await registryRoot.readString(componentsPath);
    }

    _verifyIntegrity(
      content: content,
      trustMode: trustMode,
      trustSha256: trustSha256,
      skipIntegrity: skipIntegrity,
      logger: logger,
    );

    final registry = await fromContent(
      content: content,
      registryRoot: registryRoot,
      sourceRoot: sourceRoot,
      schemaPath: schemaPath,
      skipIntegrity: skipIntegrity,
      logger: logger,
    );

    if (!offline && cachePath != null && registryRoot.isRemote) {
      try {
        final cacheFile = File(cachePath);
        if (!await cacheFile.parent.exists()) {
          await cacheFile.parent.create(recursive: true);
        }
        await cacheFile.writeAsString(content);
      } catch (e) {
        logger?.warn('Failed to cache components.json: $e');
      }
    }

    return registry;
  }

  static Future<Registry> fromContent({
    required String content,
    required RegistryLocation registryRoot,
    required RegistryLocation sourceRoot,
    String? schemaPath,
    bool skipIntegrity = false,
    CliLogger? logger,
  }) async {
    final Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('components.json must be a JSON object');
      }
      data = decoded;
    } on FormatException catch (e) {
      throw RegistrySchemaValidationException([
        'components.json is not valid JSON: ${e.message}',
      ]);
    }
    _assertSupportedComponentSchemaVersion(data);
    if (!skipIntegrity) {
      final schemaSource = ComponentsSchemaValidator.resolveSchemaSource(
        data: data,
        registryRoot: registryRoot,
        schemaPathOverride: schemaPath,
      );
      if (schemaSource == null) {
        return Registry(data, registryRoot, sourceRoot);
      }
      final result = await ComponentsSchemaValidator.validateWithJsonSchema(
        data,
        schemaSource,
      );
      if (!result.isValid) {
        throw RegistrySchemaValidationException(result.errors);
      }
    }

    return Registry(data, registryRoot, sourceRoot);
  }

  static void _assertSupportedComponentSchemaVersion(
    Map<String, dynamic> data,
  ) {
    final version = data['schemaVersion'];
    if (version != null && version != 1) {
      throw RegistrySchemaValidationException([
        'components.json schemaVersion must be 1; received $version.',
      ]);
    }
  }

  Map<String, String> get defaults {
    return Map<String, String>.from(data['defaults'] ?? {});
  }

  List<SharedItem> get shared {
    final raw = data['shared'];
    if (raw is! List) {
      return [];
    }
    return raw.map((e) => SharedItem.fromJson(e)).toList();
  }

  List<Component> get components {
    final cached = _componentsCache;
    if (cached != null) {
      return cached;
    }
    final raw = data['components'];
    if (raw is! List) {
      _componentsCache = const [];
      return _componentsCache!;
    }
    _componentsCache = List.unmodifiable(
      raw.map((e) => Component.fromJson(e)),
    );
    return _componentsCache!;
  }

  Component? getComponent(String name) {
    final lookup = _componentLookupCache ??= _buildComponentLookup();
    return lookup[name] ?? lookup[name.toLowerCase()];
  }

  Map<String, Component> _buildComponentLookup() {
    final lookup = <String, Component>{};
    for (final component in components) {
      lookup.putIfAbsent(component.id, () => component);
      lookup.putIfAbsent(component.id.toLowerCase(), () => component);
      lookup.putIfAbsent(component.name.toLowerCase(), () => component);
    }
    return lookup;
  }

  Future<List<int>> readSourceBytes(String relativePath) {
    return sourceRoot.readBytes(relativePath);
  }

  String describeSource(String relativePath) {
    return sourceRoot.describe(relativePath);
  }

  static void _verifyIntegrity({
    required String content,
    required String? trustMode,
    required String? trustSha256,
    required bool skipIntegrity,
    required CliLogger? logger,
  }) {
    if (skipIntegrity) {
      return;
    }
    if ((trustMode ?? '').trim().toLowerCase() != 'sha256') {
      return;
    }
    final expected = trustSha256?.trim().toLowerCase();
    if (expected == null || expected.isEmpty) {
      return;
    }
    final digest =
        sha256.convert(utf8.encode(content)).toString().toLowerCase();
    logger?.detail('components.json sha256: $digest');
    if (digest != expected) {
      throw Exception(
        'Integrity check failed: expected $expected but received $digest',
      );
    }
  }
}
