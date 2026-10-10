import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/registry_source.dart';
import 'package:flutter_shadcn_cli/src/application/services/version/version_manager.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:path/path.dart' as p;

/// Resolves which [RegistrySource] a command reads from (plan §9.5).
///
/// Precedence:
/// 1. `--registry <path|url>` (the only registry selector the v2 CLI needs);
/// 2. `SHADCN_REGISTRY_ROOT` / `SHADCN_REGISTRY_URL` (test + CI hooks);
/// 3. the project's `.shadcn/config.json` (`registryPath` / `registryUrl`);
/// 4. the default remote: GitHub raw at the ref matching the CLI version.
///
/// A remote source always gets an on-disk [RegistryCache] under
/// `<projectRoot>/.shadcn/cache/registry`, so `--offline` re-installs work.
class RegistrySourceResolver {
  const RegistrySourceResolver._();

  /// GitHub raw host the default registry is served from.
  static const String defaultRegistryHost =
      'https://raw.githubusercontent.com/mibrar-dev/shadcn_flutter_kit';

  /// Sub-path of the registry inside the kit repository.
  static const String defaultRegistrySubPath =
      'flutter_shadcn_kit/lib/registry';

  /// The ref the default remote pins to: the tag matching the CLI version.
  static String defaultRef() => 'v${VersionManager.currentVersion}';

  /// Default registry root URL, e.g.
  /// `https://raw.githubusercontent.com/mibrar-dev/shadcn_flutter_kit/v0.2.7/flutter_shadcn_kit/lib/registry`.
  static String defaultBaseUrl({String? ref}) =>
      '$defaultRegistryHost/${ref ?? defaultRef()}/$defaultRegistrySubPath';

  /// Builds a source for [projectRoot].
  ///
  /// [registryOverride] is the raw `--registry` value. [httpClient] is injected
  /// in tests; production uses [HttpRegistryHttpClient].
  static RegistrySource resolve({
    required String projectRoot,
    required ShadcnConfig config,
    String? registryOverride,
    bool offline = false,
    RegistryHttpClient? httpClient,
  }) {
    final rawOverride = _trim(registryOverride);
    final String? localPath;
    final String? remoteUrl;
    if (rawOverride != null) {
      localPath = _isUrl(rawOverride) ? null : rawOverride;
      remoteUrl = _isUrl(rawOverride) ? rawOverride : null;
    } else if (_env('SHADCN_REGISTRY_ROOT') != null) {
      localPath = _env('SHADCN_REGISTRY_ROOT');
      remoteUrl = null;
    } else if (_env('SHADCN_REGISTRY_URL') != null) {
      localPath = null;
      remoteUrl = _env('SHADCN_REGISTRY_URL');
    } else {
      localPath = _trim(config.registryPath);
      remoteUrl = _trim(config.registryUrl);
    }

    if (localPath != null) {
      final resolved = _resolveLocal(projectRoot, localPath);
      if (!Directory(resolved).existsSync()) {
        throw RegistrySourceException('Local registry not found: $resolved');
      }
      return LocalRegistrySource(resolved);
    }
    final base = remoteUrl ?? defaultBaseUrl();
    return RemoteRegistrySource(
      baseUrl: base,
      client: httpClient ?? HttpRegistryHttpClient(),
      cache: RegistryCache(cacheRootFor(projectRoot)),
      offline: offline,
    );
  }

  static bool _isUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  /// Project-relative cache directory for remote registry files.
  static String cacheRootFor(String projectRoot) =>
      p.join(projectRoot, '.shadcn', 'cache', 'registry');

  static String _resolveLocal(String projectRoot, String path) {
    final trimmed = path.trim();
    if (p.isAbsolute(trimmed)) {
      return p.normalize(trimmed);
    }
    return p.normalize(p.join(projectRoot, trimmed));
  }

  static String? _trim(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String? _env(String name) {
    final value = Platform.environment[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}
