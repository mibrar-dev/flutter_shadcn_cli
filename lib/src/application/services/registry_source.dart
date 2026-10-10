import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer_file_install_part.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Registry source for the v2 manifest (P5_CLI_PLAN.md §9.5).
///
/// One registry is a flat tree under `lib/registry/`: `manifests/registry.json`,
/// `themes/*.json`, `foundation/`, `theme/`, `primitives/` and `components/`.
/// A source only knows how to read a registry-relative path; the installer and
/// the theme flow share it through [RegistryFileReader] / a plain closure.
///
/// Remote is the default (GitHub raw at the ref matching the CLI version).
/// `--registry <path|url>` selects a local directory or another base URL. Every
/// HTTP call goes through an injectable [RegistryHttpClient] so tests never hit
/// the network, and a [RegistryCache] keeps downloads for offline re-installs.
abstract class RegistrySource {
  /// Raw bytes of [relPath], or `null` when the registry does not have it.
  Future<List<int>?> readBytes(String relPath);

  /// UTF-8 text of [relPath], or `null` when missing.
  Future<String?> readString(String relPath);

  /// Human-readable origin of [relPath], used in messages.
  String describe(String relPath);

  /// True for an HTTP-backed source.
  bool get isRemote;

  /// Local registry directory when the source is on disk, else `null`.
  String? get localRoot;
}

/// A registry source failed to read a file (network error, offline cache miss).
class RegistrySourceException implements Exception {
  const RegistrySourceException(this.message, {this.details = const []});

  final String message;
  final List<String> details;

  @override
  String toString() => details.isEmpty
      ? 'RegistrySourceException: $message'
      : 'RegistrySourceException: $message\n${details.join('\n')}';
}

/// Reads a local registry checkout.
class LocalRegistrySource implements RegistrySource {
  const LocalRegistrySource(this.root);

  /// Absolute registry root (the directory holding `manifests/`, `foundation/`).
  final String root;

  @override
  bool get isRemote => false;

  @override
  String? get localRoot => root;

  @override
  Future<List<int>?> readBytes(String relPath) async {
    final file = File(p.join(root, p.normalize(relPath)));
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  @override
  Future<String?> readString(String relPath) async {
    final bytes = await readBytes(relPath);
    return bytes == null ? null : decodeRegistryText(bytes);
  }

  @override
  String describe(String relPath) => p.join(root, relPath);
}

/// One HTTP response, kept free of `package:http` so fakes stay trivial.
class RegistryHttpResponse {
  const RegistryHttpResponse(this.statusCode, this.bodyBytes);

  final int statusCode;
  final List<int> bodyBytes;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// The HTTP seam for [RemoteRegistrySource]. Tests inject a fake.
abstract class RegistryHttpClient {
  Future<RegistryHttpResponse> get(Uri uri);

  void close() {}
}

/// Default [RegistryHttpClient] over `package:http`.
class HttpRegistryHttpClient implements RegistryHttpClient {
  HttpRegistryHttpClient(
      {http.Client? client, this.timeout = const Duration(seconds: 20)})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  @override
  Future<RegistryHttpResponse> get(Uri uri) async {
    final response = await _client.get(uri).timeout(timeout);
    return RegistryHttpResponse(response.statusCode, response.bodyBytes);
  }

  @override
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

/// On-disk cache for remote registry files (offline re-installs).
///
/// Files are stored under [root] by their registry-relative path, so a cached
/// tree mirrors the registry. [RemoteRegistrySource] writes on a successful
/// fetch and reads when offline.
class RegistryCache {
  const RegistryCache(this.root);

  final String root;

  Future<List<int>?> read(String relPath) async {
    final file = File(p.join(root, p.normalize(relPath)));
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  Future<void> write(String relPath, List<int> bytes) async {
    final file = File(p.join(root, p.normalize(relPath)));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  bool containsSync(String relPath) =>
      File(p.join(root, p.normalize(relPath))).existsSync();
}

/// Reads a remote registry over HTTP, optionally caching every response.
class RemoteRegistrySource implements RegistrySource {
  RemoteRegistrySource({
    required this.baseUrl,
    required this.client,
    this.cache,
    this.offline = false,
  });

  /// Base URL of the registry root, without a trailing slash.
  final String baseUrl;

  final RegistryHttpClient client;

  /// When set, successful reads are cached and offline reads come from it.
  final RegistryCache? cache;

  /// When true, only [cache] is read; the network is never touched.
  final bool offline;

  @override
  bool get isRemote => true;

  @override
  String? get localRoot => null;

  @override
  Future<List<int>?> readBytes(String relPath) async {
    final normalized = p.posix.normalize(relPath.replaceAll('\\', '/'));
    if (offline) {
      final cached = await cache?.read(normalized);
      if (cached == null) {
        throw RegistrySourceException(
          'Offline mode: no cached copy of ${describe(relPath)}.',
        );
      }
      return cached;
    }
    final uri = _resolve(normalized);
    final RegistryHttpResponse response;
    try {
      response = await client.get(uri);
    } catch (error) {
      final cached = await cache?.read(normalized);
      if (cached != null) {
        return cached;
      }
      throw RegistrySourceException(
        'Failed to fetch $uri',
        details: ['$error'],
      );
    }
    if (response.statusCode == 404) {
      return null;
    }
    if (!response.isSuccess) {
      throw RegistrySourceException(
        'Failed to fetch $uri (HTTP ${response.statusCode})',
      );
    }
    await cache?.write(normalized, response.bodyBytes);
    return response.bodyBytes;
  }

  @override
  Future<String?> readString(String relPath) async {
    final bytes = await readBytes(relPath);
    return bytes == null ? null : decodeRegistryText(bytes);
  }

  @override
  String describe(String relPath) =>
      _resolve(p.posix.normalize(relPath.replaceAll('\\', '/'))).toString();

  Uri _resolve(String relPath) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$base/$relPath');
  }
}

/// Adapts a [RegistrySource] to the installer's [RegistryFileReader] contract.
class RegistrySourceFileReader implements RegistryFileReader {
  const RegistrySourceFileReader(this.source);

  final RegistrySource source;

  @override
  Future<List<int>?> readBytes(String relPath) => source.readBytes(relPath);

  @override
  Future<String?> readString(String relPath) => source.readString(relPath);
}
