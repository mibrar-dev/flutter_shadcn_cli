import 'dart:convert';

import 'package:flutter_shadcn_cli/src/application/services/theme/theme_models.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_schema_validator.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:flutter_shadcn_cli/src/registry/registry_location.dart';

/// Reads a registry-relative path and returns UTF-8 text, or `null` when the
/// registry does not have the file.
///
/// A bare function type keeps the theme flow independent of whichever reader
/// the caller already has: B4's `RegistryFileReader`, `RegistryLocation`, a
/// cache directory or a test fixture all adapt with one closure.
typedef ThemeRegistryReader = Future<String?> Function(String relPath);

/// Reads the registry pieces the theme flow needs: the v2 manifest and the
/// preset JSONs it points at.
class ThemeRegistrySource {
  ThemeRegistrySource({
    required ThemeRegistryReader read,
    required String Function(String relPath) describe,
    this.registryRoot,
  })  : _read = read,
        _describe = describe;

  /// Adapts any reader with the shape `Future<String?> Function(String)`:
  /// B5's `RegistrySource`, B4's `RegistryFileReader`, a cache or a test
  /// fixture. The `describe` and `registryRoot` arguments are optional;
  /// without them messages fall back to the bare registry-relative path.
  ///
  /// ```dart
  /// ThemeRegistrySource.overReader(
  ///   source.readString,                       // RegistrySource (B5)
  ///   registryRoot: source.localRoot,
  ///   describe: source.describe,
  /// )
  /// ```
  factory ThemeRegistrySource.overReader(
    Future<String?> Function(String relPath) read, {
    String? registryRoot,
    String Function(String relPath)? describe,
  }) {
    return ThemeRegistrySource(
      read: read,
      describe: describe ?? (relPath) => relPath,
      registryRoot: registryRoot,
    );
  }

  /// Adapts the kept `RegistryLocation`, which already abstracts a local
  /// directory from a remote base URL.
  factory ThemeRegistrySource.overLocation(RegistryLocation location) {
    return ThemeRegistrySource(
      read: location.readString,
      describe: location.describe,
      registryRoot: location.isRemote ? null : location.root,
    );
  }

  /// Registry-relative path of the generated manifest.
  static const String manifestPath = 'manifests/registry.json';

  final ThemeRegistryReader _read;
  final String Function(String relPath) _describe;

  /// Local registry directory, when there is one. On-disk checks in the
  /// validator only run for a local registry.
  final String? registryRoot;

  /// Loads `manifests/registry.json` and validates it against the v2 rules.
  ///
  /// The theme flow runs the **full** [ManifestSchemaValidator]: a manifest
  /// whose layers, deps or `fileHashes` are broken cannot be installed from
  /// either, so serving presets from it would only defer the error. The
  /// generated kit manifest satisfies every rule (`themes/*.json` are hashed,
  /// and primitive cycles are legal per plan §9.7).
  ///
  /// Preset documents themselves are checked against `themes.schema.json` by
  /// [ThemeService.apply]. Throws [ThemeApplyException] on any failure.
  Future<RegistryManifest> loadManifest() async {
    final decoded = _decode(await _readOrFail(manifestPath), manifestPath);
    final result =
        ManifestSchemaValidator.validate(decoded, registryRoot: registryRoot);
    if (!result.isValid) {
      throw ThemeApplyException(
        '${_describe(manifestPath)} is not a valid registry manifest '
        '(schemaVersion 2).',
        details: result.errors,
      );
    }
    return RegistryManifest.fromJson(decoded);
  }

  /// Reads and decodes a registry-relative JSON document, e.g.
  /// `themes/vercel.json`.
  Future<Map<String, dynamic>> readJson(String relPath) async {
    return _decode(await _readOrFail(relPath), relPath);
  }

  /// Human readable origin of [relPath], used in messages.
  String describe(String relPath) => _describe(relPath);

  /// [ThemeRegistryReader] with every transport failure normalised.
  ///
  /// A `RegistryLocation` throws a bare `Exception` ("File not found", an HTTP
  /// status, an offline refusal), which would otherwise escape the callers'
  /// `ThemeApplyException` handling and abort `init` with a stack trace.
  Future<String> _readOrFail(String relPath) async {
    try {
      final text = await _read(relPath);
      if (text == null) {
        throw ThemeApplyException(
          'Registry file not found: ${_describe(relPath)}',
        );
      }
      return text;
    } on ThemeApplyException {
      rethrow;
    } catch (error) {
      throw ThemeApplyException(
        'Cannot read ${_describe(relPath)}: $error',
      );
    }
  }

  Map<String, dynamic> _decode(String text, String relPath) {
    try {
      final raw = jsonDecode(text);
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('document root must be a JSON object');
      }
      return raw;
    } on FormatException catch (error) {
      throw ThemeApplyException('${_describe(relPath)}: ${error.message}');
    }
  }
}

/// Builds a [ThemeRegistrySource] from the project's `.shadcn/config.json`.
///
/// Resolution order: the explicit `--registry` override, then the namespace's
/// registry entry, then the top-level `registryPath` / `registryUrl`. An
/// http(s) root is read as a remote base, anything else as a local directory.
class ThemeRegistrySourceResolver {
  const ThemeRegistrySourceResolver._();

  /// The configured registry source, or `null` when the project has no
  /// registry configured at all.
  static ThemeRegistrySource? fromConfig(
    ShadcnConfig config, {
    String? namespace,
    String? registryPathOverride,
    String? registryUrlOverride,
    bool offline = false,
  }) {
    final entry = config.registryConfig(namespace);
    final roots = <String?>[
      _trimmed(registryUrlOverride),
      _trimmed(config.registryUrl),
      _trimmed(entry?.registryUrl),
      _trimmed(entry?.baseUrl),
      _trimmed(registryPathOverride),
      _trimmed(config.registryPath),
      _trimmed(entry?.registryPath),
    ];
    for (final root in roots) {
      if (root != null) return _sourceForRoot(root, offline: offline);
    }
    return null;
  }

  /// [fromConfig], but throws a [ThemeApplyException] with actionable text.
  static ThemeRegistrySource requireFromConfig(
    ShadcnConfig config, {
    String? namespace,
    String? registryPathOverride,
    String? registryUrlOverride,
    bool offline = false,
  }) {
    final source = fromConfig(
      config,
      namespace: namespace,
      registryPathOverride: registryPathOverride,
      registryUrlOverride: registryUrlOverride,
      offline: offline,
    );
    if (source == null) {
      throw const ThemeApplyException(
        'No shadcn registry is configured for this project. Run '
        '"flutter_shadcn init" first, or pass --registry <path|url>.',
      );
    }
    return source;
  }

  static ThemeRegistrySource _sourceForRoot(
    String root, {
    required bool offline,
  }) {
    final uri = Uri.tryParse(root);
    final remote = uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https');
    if (remote) {
      return ThemeRegistrySource.overLocation(
        RegistryLocation.remote(root, offline: offline),
      );
    }
    final path =
        root.startsWith('file://') ? Uri.parse(root).toFilePath() : root;
    return ThemeRegistrySource.overLocation(
      RegistryLocation.local(path, offline: offline),
    );
  }

  static String? _trimmed(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
