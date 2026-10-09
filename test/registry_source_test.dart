import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/registry_source.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_source_resolver.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _FakeHttp implements RegistryHttpClient {
  _FakeHttp({this.bodies = const {}, this.fail = false});

  final Map<String, List<int>> bodies;
  final bool fail;
  final List<Uri> requests = [];

  @override
  Future<RegistryHttpResponse> get(Uri uri) async {
    requests.add(uri);
    if (fail) {
      throw const SocketException('no network');
    }
    final body = bodies[uri.toString()];
    if (body == null) {
      return const RegistryHttpResponse(404, []);
    }
    return RegistryHttpResponse(200, body);
  }

  @override
  void close() {}
}

void main() {
  group('LocalRegistrySource', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('registry_source_local_');
      File(p.join(dir.path, 'foundation', 'data.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('class Data {}\n');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('reads an existing file and reports a missing one as null', () async {
      final source = LocalRegistrySource(dir.path);
      expect(
          await source.readString('foundation/data.dart'), 'class Data {}\n');
      expect(await source.readBytes('foundation/missing.dart'), isNull);
      expect(source.isRemote, isFalse);
      expect(source.localRoot, dir.path);
    });
  });

  group('RemoteRegistrySource', () {
    test('fetches over HTTP and caches the response', () async {
      final cacheDir =
          Directory.systemTemp.createTempSync('registry_source_cache_');
      addTearDown(() => cacheDir.deleteSync(recursive: true));
      final cache = RegistryCache(cacheDir.path);
      final client = _FakeHttp(bodies: {
        'https://example.com/registry/foundation/data.dart':
            utf8.encode('class Data {}\n'),
      });
      final source = RemoteRegistrySource(
        baseUrl: 'https://example.com/registry',
        client: client,
        cache: cache,
      );

      expect(
        await source.readString('foundation/data.dart'),
        'class Data {}\n',
      );
      expect(cache.containsSync('foundation/data.dart'), isTrue);
      expect(await cache.read('foundation/data.dart'), isNotNull);
    });

    test('returns null for a 404', () async {
      final source = RemoteRegistrySource(
        baseUrl: 'https://example.com/registry',
        client: _FakeHttp(),
      );
      expect(await source.readBytes('nope.dart'), isNull);
    });

    test('throws on a network error without a cached copy', () async {
      final source = RemoteRegistrySource(
        baseUrl: 'https://example.com/registry',
        client: _FakeHttp(fail: true),
      );
      expect(
        source.readBytes('foundation/data.dart'),
        throwsA(isA<RegistrySourceException>()),
      );
    });

    test('falls back to the cache when the network fails', () async {
      final cacheDir =
          Directory.systemTemp.createTempSync('registry_source_cache_');
      addTearDown(() => cacheDir.deleteSync(recursive: true));
      final cache = RegistryCache(cacheDir.path);
      await cache.write('foundation/data.dart', utf8.encode('cached\n'));
      final source = RemoteRegistrySource(
        baseUrl: 'https://example.com/registry',
        client: _FakeHttp(fail: true),
        cache: cache,
      );
      expect(await source.readString('foundation/data.dart'), 'cached\n');
    });

    test('offline reads the cache and throws without one', () async {
      final cacheDir =
          Directory.systemTemp.createTempSync('registry_source_cache_');
      addTearDown(() => cacheDir.deleteSync(recursive: true));
      final cache = RegistryCache(cacheDir.path);
      await cache.write('foundation/data.dart', utf8.encode('cached\n'));
      final client = _FakeHttp(bodies: {
        'https://example.com/registry/foundation/data.dart':
            utf8.encode('network\n'),
      });
      final source = RemoteRegistrySource(
        baseUrl: 'https://example.com/registry',
        client: client,
        cache: cache,
        offline: true,
      );

      expect(await source.readString('foundation/data.dart'), 'cached\n');
      expect(client.requests, isEmpty);
      expect(
        source.readBytes('foundation/missing.dart'),
        throwsA(isA<RegistrySourceException>()),
      );
    });
  });

  group('RegistrySourceFileReader', () {
    test('delegates to the wrapped source', () async {
      final dir = Directory.systemTemp.createTempSync('registry_reader_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, 'a.dart')).writeAsStringSync('a\n');
      final reader = RegistrySourceFileReader(LocalRegistrySource(dir.path));

      expect(await reader.readString('a.dart'), 'a\n');
      expect(await reader.readBytes('missing.dart'), isNull);
    });
  });

  group('RegistrySourceResolver', () {
    test('resolves a local directory from the --registry override', () {
      final dir = Directory.systemTemp.createTempSync('registry_resolver_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = RegistrySourceResolver.resolve(
        projectRoot: dir.path,
        config: const ShadcnConfig(),
        registryOverride: dir.path,
      );
      expect(source, isA<LocalRegistrySource>());
      expect(source.localRoot, dir.path);
    });

    test('rejects a missing local registry', () {
      expect(
        () => RegistrySourceResolver.resolve(
          projectRoot: Directory.systemTemp.path,
          config: const ShadcnConfig(),
          registryOverride: '/definitely/not/here',
        ),
        throwsA(isA<RegistrySourceException>()),
      );
    });

    test('resolves a remote URL override', () {
      final source = RegistrySourceResolver.resolve(
        projectRoot: Directory.systemTemp.path,
        config: const ShadcnConfig(),
        registryOverride: 'https://example.com/registry',
      );
      expect(source, isA<RemoteRegistrySource>());
      expect((source as RemoteRegistrySource).baseUrl,
          'https://example.com/registry');
      source.client.close();
    });

    test('falls back to the version-pinned default remote', () {
      final source = RegistrySourceResolver.resolve(
        projectRoot: Directory.systemTemp.path,
        config: const ShadcnConfig(),
      );
      expect(source, isA<RemoteRegistrySource>());
      final base = (source as RemoteRegistrySource).baseUrl;
      expect(base, startsWith(RegistrySourceResolver.defaultRegistryHost));
      expect(base, contains('/flutter_shadcn_kit/lib/registry'));
      source.client.close();
    });

    test('uses the config registry path', () {
      final dir = Directory.systemTemp.createTempSync('registry_resolver_cfg_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = RegistrySourceResolver.resolve(
        projectRoot: dir.path,
        config: ShadcnConfig(registryPath: dir.path),
      );
      expect(source, isA<LocalRegistrySource>());
    });

    test('default base URL pins the CLI version ref', () {
      expect(RegistrySourceResolver.defaultBaseUrl(ref: 'v9.9.9'),
          contains('/v9.9.9/'));
      expect(RegistrySourceResolver.defaultRef(), startsWith('v'));
    });
  });
}
