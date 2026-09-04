import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/resolver_v1.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class RegistryLocation {
  final String root;
  final bool isRemote;
  final bool offline;
  final http.Client _client;

  RegistryLocation.local(this.root, {this.offline = false})
      : isRemote = false,
        _client = http.Client();

  RegistryLocation.remote(this.root, {this.offline = false})
      : isRemote = true,
        _client = http.Client();

  Future<List<int>> readBytes(String relativePath) async {
    if (isRemote) {
      if (offline) {
        throw Exception('Offline mode: remote access disabled.');
      }
      // Try v1 layout fallbacks: `manifests/` prefix and `registry/`
      // prefix. Remote layout is `registry/manifests/` under the source
      // root, but legacy callers resolve `components.json` against the
      // registry root (`.../lib/registry`) or `shared/...` against the
      // source root (`.../lib`). Without fallbacks those 404 as
      // `.../lib/registry/components.json` or `.../lib/shared/...`
      // instead of `.../lib/registry/manifests/components.json` and
      // `.../lib/registry/shared/...`.
      Object? lastError;
      for (final candidate in _remotePathCandidates(relativePath)) {
        final uri = _resolveRemote(candidate);
        try {
          final response = await _client
              .get(uri)
              .timeout(const Duration(seconds: 15));
          if (response.statusCode >= 200 && response.statusCode < 300) {
            return response.bodyBytes;
          }
          lastError = Exception(
            'Failed to fetch $uri (${response.statusCode})',
          );
        } catch (e) {
          lastError = e;
        }
        final apiBytes = await _readViaGithubApi(candidate);
        if (apiBytes != null) {
          return apiBytes;
        }
      }
      final attempted = _resolveRemote(relativePath).toString();
      if (lastError != null) {
        throw Exception('Failed to fetch $attempted ($lastError)');
      }
      throw Exception('Failed to fetch $attempted (404)');
    }
    final candidates = _localPathCandidates(relativePath);
    for (final path in candidates) {
      final file = File(p.join(root, path));
      if (await file.exists()) {
        return file.readAsBytes();
      }
    }

    final attempted = File(p.join(root, relativePath)).path;
    throw Exception('File not found: $attempted');
  }

  Future<String> readString(String relativePath) async {
    final bytes = await readBytes(relativePath);
    return utf8.decode(bytes);
  }

  String describe(String relativePath) {
    if (isRemote) {
      return _resolveRemote(relativePath).toString();
    }
    return p.join(root, relativePath);
  }

  Uri _resolveRemote(String relativePath) {
    return ResolverV1.resolveUrl(root, relativePath);
  }

  Future<List<int>?> _readViaGithubApi(String relativePath) async {
    final apiUrl = ResolverV1.githubApiContentsUrl(root, relativePath);
    if (apiUrl == null) {
      return null;
    }
    final response = await _client.get(
      Uri.parse(apiUrl),
      headers: const {
        'Accept': 'application/vnd.github+json',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      return null;
    }
    final downloadUrl = decoded['download_url']?.toString();
    if (downloadUrl == null || downloadUrl.isEmpty) {
      final content = decoded['content']?.toString();
      final encoding = decoded['encoding']?.toString();
      if (encoding == 'base64' && content != null && content.isNotEmpty) {
        final normalized = content.replaceAll('\n', '');
        return base64Decode(normalized);
      }
      return null;
    }
    final raw = await _client.get(Uri.parse(downloadUrl));
    if (raw.statusCode < 200 || raw.statusCode >= 300) {
      return null;
    }
    return raw.bodyBytes;
  }

  List<String> _localPathCandidates(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    final candidates = <String>[normalized];
    void add(String value) {
      if (value.isNotEmpty && !candidates.contains(value)) {
        candidates.add(value);
      }
    }

    final rootName = p.basename(root);
    if (rootName == 'registry' && normalized.startsWith('registry/')) {
      final stripped = normalized.substring('registry/'.length);
      if (stripped.isNotEmpty) {
        add(stripped);
      }
    }
    // v1 layout: manifests live under `manifests/`. Legacy callers ask for
    // `components.json` / `index.json` / `*.schema.json` at the registry
    // root, but the file is at `manifests/<name>`.
    if (!normalized.startsWith('manifests/') &&
        !normalized.startsWith('registry/manifests/')) {
      add('manifests/$normalized');
    }
    if (!normalized.startsWith('registry/')) {
      add('registry/$normalized');
      if (!normalized.startsWith('manifests/')) {
        add('registry/manifests/$normalized');
      }
    }
    return candidates;
  }

  List<String> _remotePathCandidates(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    final candidates = <String>[normalized];
    void add(String value) {
      if (value.isNotEmpty && !candidates.contains(value)) {
        candidates.add(value);
      }
    }

    // Strip a duplicated `registry/` prefix when the root already ends
    // with `/registry` (directory entries use `registry/manifests/...`
    // relative to the source root `.../lib`).
    if (normalized.startsWith('registry/')) {
      final stripped = normalized.substring('registry/'.length);
      if (stripped.isNotEmpty) {
        add(stripped);
      }
    }
    if (!normalized.startsWith('manifests/') &&
        !normalized.startsWith('registry/manifests/')) {
      add('manifests/$normalized');
    }
    if (!normalized.startsWith('registry/')) {
      add('registry/$normalized');
      if (!normalized.startsWith('manifests/')) {
        add('registry/manifests/$normalized');
      }
    }
    // Theme artifacts (`shared/theme/generated/...`) resolved against the
    // source root (`.../lib`) need the `registry/` prefix.
    if ((normalized.startsWith('shared/') ||
            normalized.startsWith('registry/shared/')) &&
        !candidates.any((c) => c == 'registry/$normalized')) {
      // Already covered above; kept for clarity.
    }
    return candidates;
  }
}
