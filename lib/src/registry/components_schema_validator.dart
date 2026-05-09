import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/registry/registry_location.dart';
import 'package:flutter_shadcn_cli/src/registry/schema_source.dart';
import 'package:flutter_shadcn_cli/src/registry/schema_validation_result.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;

class ComponentsSchemaValidator {
  static final Map<String, Future<JsonSchema>> _schemaCache = {};

  static SchemaSource? resolveSchemaSource({
    required Map<String, dynamic> data,
    required RegistryLocation registryRoot,
    String? schemaPathOverride,
  }) {
    final override = schemaPathOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return _schemaSourceFromString(override, registryRoot);
    }

    final schemaRef = data[r'$schema'];
    if (schemaRef is String && schemaRef.trim().isNotEmpty) {
      final resolved = _schemaSourceFromString(schemaRef.trim(), registryRoot);
      if (resolved != null) {
        return resolved;
      }
    }

    return SchemaSource(
      label: registryRoot.describe('components.schema.json'),
      read: () => registryRoot.readString('components.schema.json'),
    );
  }

  static Future<SchemaValidationResult> validateWithJsonSchema(
    dynamic data,
    SchemaSource schemaSource,
  ) async {
    try {
      final schema = await _schemaFor(schemaSource);
      final result = schema.validate(data);
      final errors = result.errors.map((e) => e.toString()).toList();
      return SchemaValidationResult(isValid: result.isValid, errors: errors);
    } catch (e) {
      return SchemaValidationResult(
        isValid: false,
        errors: ['Failed to validate schema: $e'],
      );
    }
  }

  static Future<JsonSchema> _schemaFor(SchemaSource schemaSource) async {
    final cached = _schemaCache[schemaSource.label];
    if (cached != null) {
      return cached;
    }
    final future = () async {
      final schemaContent = await schemaSource.read();
      final schemaData = jsonDecode(schemaContent);
      return JsonSchema.create(schemaData);
    }();
    _schemaCache[schemaSource.label] = future;
    try {
      return await future;
    } catch (_) {
      _schemaCache.remove(schemaSource.label);
      rethrow;
    }
  }

  static SchemaSource? _schemaSourceFromString(
    String value,
    RegistryLocation registryRoot,
  ) {
    final trimmed = value.trim();
    if (_isHttpUrl(trimmed)) {
      return SchemaSource(
        label: trimmed,
        read: () async {
          final response = await http.get(Uri.parse(trimmed));
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw Exception(
              'Failed to fetch schema ($trimmed) (${response.statusCode})',
            );
          }
          return response.body;
        },
      );
    }

    if (File(trimmed).existsSync()) {
      return SchemaSource(
        label: trimmed,
        read: () => File(trimmed).readAsString(),
      );
    }

    final relative = _normalizeSchemaPath(trimmed);
    final localV1Schema = _localV1SchemaFallback(relative, registryRoot);
    if (localV1Schema != null) {
      return SchemaSource(
        label: registryRoot.describe(localV1Schema),
        read: () => registryRoot.readString(localV1Schema),
      );
    }
    return SchemaSource(
      label: registryRoot.describe(relative),
      read: () => registryRoot.readString(relative),
    );
  }

  static bool _isHttpUrl(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  static String _normalizeSchemaPath(String value) {
    var normalized = value.replaceAll('\\', '/');
    if (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    normalized = normalized.replaceFirst(RegExp(r'^/+'), '');
    return p.posix.normalize(normalized);
  }

  static String? _localV1SchemaFallback(
    String relative,
    RegistryLocation registryRoot,
  ) {
    if (registryRoot.isRemote || relative != 'components.schema.json') {
      return null;
    }
    const v1SchemaPath = 'manifests/components.schema.json';
    if (File(p.join(registryRoot.root, relative)).existsSync()) {
      return null;
    }
    if (File(p.join(registryRoot.root, v1SchemaPath)).existsSync()) {
      return v1SchemaPath;
    }
    return null;
  }
}
