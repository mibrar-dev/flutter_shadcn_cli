import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/infrastructure/validation/schema_validator.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The v1 `ComponentsSchemaValidator` / `Registry.fromContent` tests were
/// removed with the v1 manifest models (rearchitecture batch B1). The v2
/// manifest validator is covered by
/// `test/registry/manifest/manifest_schema_validator_test.dart`; this file
/// keeps the tests for the generic `SchemaValidator` infrastructure.
void main() {
  test('generic schema validator caches local schemas across instances',
      () async {
    final fixtureDir = await Directory.systemTemp.createTemp(
      'schema_validator_cache_test_',
    );
    addTearDown(() => fixtureDir.delete(recursive: true));
    final schemaFile = File(p.join(fixtureDir.path, 'generic.schema.json'));
    schemaFile.writeAsStringSync(
      jsonEncode({
        r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        'type': 'object',
        'required': ['name'],
        'properties': {
          'name': {'type': 'string'},
        },
      }),
    );

    final first = SchemaValidator();
    final second = SchemaValidator();
    addTearDown(first.close);
    addTearDown(second.close);

    final valid = await first.validate(
      data: {'name': 'first'},
      baseUrl: fixtureDir.path,
      schemaPath: 'generic.schema.json',
    );
    schemaFile.writeAsStringSync('{not-json');
    final cached = await second.validate(
      data: {'name': 'second'},
      baseUrl: fixtureDir.path,
      schemaPath: 'generic.schema.json',
    );

    expect(valid.isValid, isTrue);
    expect(cached.isValid, isTrue);
  });

  test('generic schema validator reuses remote schema across instances',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));
    var requests = 0;
    server.listen((request) async {
      requests += 1;
      request.response.write(
        jsonEncode({
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          'type': 'object',
          'required': ['name'],
          'properties': {
            'name': {'type': 'string'},
          },
        }),
      );
      await request.response.close();
    });
    final schemaUrl =
        'http://${server.address.host}:${server.port}/schema.json';
    final first = SchemaValidator();
    final second = SchemaValidator();
    addTearDown(first.close);
    addTearDown(second.close);

    final valid = await first.validate(
      data: {'name': 'first'},
      baseUrl: 'https://example.com/registry',
      schemaPath: schemaUrl,
    );
    final cached = await second.validate(
      data: {'name': 'second'},
      baseUrl: 'https://example.com/registry',
      schemaPath: schemaUrl,
    );

    expect(valid.isValid, isTrue);
    expect(cached.isValid, isTrue);
    expect(requests, 1);
  });

  test('generic schema validator does not close injected HTTP client', () {
    final client = _CloseTrackingClient();
    final validator = SchemaValidator(client: client);

    validator.close();

    expect(client.closed, isFalse);
    client.close();
    expect(client.closed, isTrue);
  });
}

class _CloseTrackingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError();
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}
