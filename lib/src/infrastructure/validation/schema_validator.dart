import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry/schema_validation_result.dart';
import 'package:flutter_shadcn_cli/src/resolver_v1.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;

class SchemaValidator {
  static final Map<String, Future<JsonSchema>> _schemaCache = {};

  final http.Client _client;
  final bool _ownsClient;

  SchemaValidator({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Future<SchemaValidationResult> validate({
    required dynamic data,
    required String baseUrl,
    required String schemaPath,
    CliLogger? logger,
  }) async {
    try {
      final schema = await _schemaFor(baseUrl: baseUrl, schemaPath: schemaPath);
      final result = schema.validate(data);
      final errors = result.errors.map((e) => e.toString()).toList();
      return SchemaValidationResult(isValid: result.isValid, errors: errors);
    } catch (e) {
      logger?.warn('Schema validation failed for "$schemaPath": $e');
      return SchemaValidationResult(
        isValid: false,
        errors: ['Failed to validate schema: $e'],
      );
    }
  }

  Future<JsonSchema> _schemaFor({
    required String baseUrl,
    required String schemaPath,
  }) async {
    final key = _cacheKey(baseUrl: baseUrl, schemaPath: schemaPath);
    final cached = _schemaCache[key];
    if (cached != null) {
      return cached;
    }
    final future = () async {
      final schemaContent = await _readSchema(
        baseUrl: baseUrl,
        schemaPath: schemaPath,
      );
      final schemaData = jsonDecode(schemaContent);
      return JsonSchema.create(schemaData);
    }();
    _schemaCache[key] = future;
    try {
      return await future;
    } catch (_) {
      _schemaCache.remove(key);
      rethrow;
    }
  }

  String _cacheKey({
    required String baseUrl,
    required String schemaPath,
  }) {
    final trimmedSchemaPath = schemaPath.trim();
    if (_isHttpUrl(trimmedSchemaPath)) {
      return trimmedSchemaPath;
    }
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || uri.scheme == 'file') {
      final rootPath =
          uri != null && uri.scheme == 'file' ? uri.toFilePath() : baseUrl;
      return p.normalize(p.join(rootPath, trimmedSchemaPath));
    }
    return ResolverV1.resolveUrl(
      baseUrl,
      ResolverV1.normalizeRelativePath(trimmedSchemaPath),
    ).toString();
  }

  Future<String> _readSchema({
    required String baseUrl,
    required String schemaPath,
  }) async {
    final trimmedSchemaPath = schemaPath.trim();
    if (trimmedSchemaPath.isEmpty) {
      throw Exception('schemaPath cannot be empty');
    }

    if (_isHttpUrl(trimmedSchemaPath)) {
      final response = await _client.get(Uri.parse(trimmedSchemaPath));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Failed to fetch schema $trimmedSchemaPath (${response.statusCode})',
        );
      }
      return response.body;
    }

    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || uri.scheme == 'file') {
      final rootPath =
          uri != null && uri.scheme == 'file' ? uri.toFilePath() : baseUrl;
      final localPath = p.normalize(p.join(rootPath, trimmedSchemaPath));
      final file = File(localPath);
      if (!file.existsSync()) {
        throw Exception('Schema file not found: $localPath');
      }
      return file.readAsString();
    }

    final schemaUri = ResolverV1.resolveUrl(
      baseUrl,
      ResolverV1.normalizeRelativePath(trimmedSchemaPath),
    );
    final response = await _client.get(schemaUri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to fetch schema ${schemaUri.toString()} (${response.statusCode})',
      );
    }
    return response.body;
  }

  bool _isHttpUrl(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }
}
