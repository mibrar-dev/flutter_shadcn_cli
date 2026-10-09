import 'dart:convert';

import 'package:flutter_shadcn_cli/src/application/services/theme/theme_models.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
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

  /// Loads `manifests/registry.json` and checks the parts the theme flow uses.
  ///
  /// Deliberately scoped: whole-manifest validation (deps closure, layer
  /// files, `fileHashes` coverage) belongs to `validate`/`doctor`, and the
  /// generated kit manifest does not satisfy every rule that validator
  /// enforces today (its primitive graph has cycles per plan §9.7, and
  /// `themes/*.json` carry no `fileHashes` entry). Here the hard rules are the
  /// ones a preset cannot work without:
  ///
  /// - `schemaVersion` must be 2 (anything else is the retired v1 manifest);
  /// - `themes` must be an object of `{file, name, modes}` entries;
  /// - `install.root` is used as the default install root.
  ///
  /// Preset documents themselves are checked against `themes.schema.json` by
  /// [ThemeService.apply]. Throws [ThemeApplyException] on any failure.
  Future<RegistryManifest> loadManifest() async {
    final text = await _readOrFail(manifestPath);
    final decoded = _decode(text, manifestPath);
    if (decoded['schemaVersion'] != 2) {
      throw ThemeApplyException(
        '${_describe(manifestPath)} has schemaVersion '
        '${decoded['schemaVersion']}; this CLI needs the v2 manifest.',
      );
    }
    final errors = <String>[];
    final themes = decoded['themes'];
    if (themes is! Map) {
      errors.add('`themes` must be an object of preset entries.');
    } else {
      themes.forEach((id, entry) {
        if (entry is! Map) {
          errors.add('themes.$id must be an object.');
          return;
        }
        final file = entry['file']?.toString().trim() ?? '';
        final name = entry['name']?.toString().trim() ?? '';
        final modes = entry['modes'];
        if (file.isEmpty) errors.add('themes.$id.file is required.');
        if (name.isEmpty) errors.add('themes.$id.name is required.');
        if (modes is! List || modes.isEmpty) {
          errors.add('themes.$id.modes must be a non-empty array.');
        }
      });
    }
    if (errors.isNotEmpty) {
      throw ThemeApplyException(
        '${_describe(manifestPath)} has no usable `themes` section.',
        details: errors,
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
