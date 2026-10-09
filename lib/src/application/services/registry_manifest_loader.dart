import 'dart:convert';

import 'package:flutter_shadcn_cli/src/application/services/lockfile/hashing.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_source.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_schema_validator.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:flutter_shadcn_cli/src/registry/schema_validation_result.dart';

/// Registry-relative path of the single generated v2 manifest.
const String kRegistryManifestPath = 'manifests/registry.json';

/// A loaded and validated manifest plus the digest `shadcn.lock` records.
class LoadedRegistryManifest {
  const LoadedRegistryManifest({
    required this.manifest,
    required this.sha256,
    required this.rawJson,
    required this.path,
  });

  final RegistryManifest manifest;

  /// Lowercase hex sha256 of the exact manifest bytes.
  final String sha256;

  /// The decoded document, kept for callers that need untouched data.
  final Map<String, dynamic> rawJson;

  /// Registry-relative path the manifest was read from.
  final String path;
}

/// The manifest could not be read, decoded or validated.
class RegistryManifestException implements Exception {
  const RegistryManifestException(
    this.message, {
    this.details = const [],
    this.notFound = false,
    this.isSchemaInvalid = false,
  });

  final String message;
  final List<String> details;

  /// True when the registry has no manifest at the expected path (404).
  final bool notFound;

  /// True when the failure is a schema violation (exit code 3 / 20).
  final bool isSchemaInvalid;

  @override
  String toString() => details.isEmpty
      ? 'RegistryManifestException: $message'
      : 'RegistryManifestException: $message\n${details.join('\n')}';
}

/// Reads `manifests/registry.json` from a [RegistrySource], validates it
/// against the v2 rules and digests it (plan §1.3, §2.5).
///
/// Every command that touches the registry loads through here so a corrupt or
/// v1 manifest fails the same way everywhere.
class RegistryManifestLoader {
  const RegistryManifestLoader(this.source);

  final RegistrySource source;

  Future<LoadedRegistryManifest> load(
      {String path = kRegistryManifestPath}) async {
    // A read failure (network, offline cache miss) propagates as
    // [RegistrySourceException] so callers map it to the network/offline exit
    // codes rather than a schema error.
    final bytes = await source.readBytes(path);
    if (bytes == null) {
      throw RegistryManifestException(
        'Registry manifest not found: ${source.describe(path)}.',
        notFound: true,
      );
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      throw RegistryManifestException(
        '${source.describe(path)} is not valid JSON (${error.message}).',
        isSchemaInvalid: true,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw RegistryManifestException(
        '${source.describe(path)} must contain a JSON object.',
        isSchemaInvalid: true,
      );
    }

    final validation = ManifestSchemaValidator.validate(
      decoded,
      registryRoot: source.localRoot,
    );
    if (!validation.isValid) {
      throw RegistryManifestException(
        '${source.describe(path)} failed v2 schema validation '
        '(${validation.errors.length} issue(s)).',
        details: validation.errors,
        isSchemaInvalid: true,
      );
    }

    return LoadedRegistryManifest(
      manifest: RegistryManifest.fromJson(decoded),
      sha256: FileHashing.ofBytes(bytes),
      rawJson: decoded,
      path: path,
    );
  }
}

/// Convenience alias so callers can name the validation result explicitly.
typedef ManifestValidationResult = SchemaValidationResult;
