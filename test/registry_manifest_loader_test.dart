import 'package:flutter_shadcn_cli/src/application/services/registry_manifest_loader.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_source.dart';
import 'package:test/test.dart';

import 'support/v2_registry_fixture.dart';

void main() {
  group('RegistryManifestLoader', () {
    late V2RegistryFixture fixture;

    setUp(() => fixture = V2RegistryFixture.create());
    tearDown(() => fixture.dispose());

    test('loads and validates the fixture manifest', () async {
      final loaded =
          await RegistryManifestLoader(LocalRegistrySource(fixture.root))
              .load();

      expect(loaded.manifest.schemaVersion, 2);
      expect(loaded.manifest.components.keys, containsAll(['button', 'input']));
      expect(loaded.manifest.themes.keys, ['vercel']);
      expect(loaded.sha256, hasLength(64));
      expect(loaded.path, 'manifests/registry.json');
    });

    test('digest is stable across loads', () async {
      final loader = RegistryManifestLoader(LocalRegistrySource(fixture.root));
      final first = await loader.load();
      final second = await loader.load();
      expect(first.sha256, second.sha256);
    });

    test('rejects a missing manifest as not-found', () async {
      final source = LocalRegistrySource('${fixture.root}/missing-root');
      try {
        await RegistryManifestLoader(source).load();
        fail('expected a RegistryManifestException');
      } on RegistryManifestException catch (error) {
        expect(error.notFound, isTrue);
        expect(error.isSchemaInvalid, isFalse);
      }
    });

    test('rejects a v1 manifest as schema-invalid', () async {
      fixture.writeManifest({
        'schemaVersion': 1,
        'registry': {'name': 'old', 'version': '1'},
      });
      try {
        await RegistryManifestLoader(LocalRegistrySource(fixture.root)).load();
        fail('expected a RegistryManifestException');
      } on RegistryManifestException catch (error) {
        expect(error.isSchemaInvalid, isTrue);
        expect(error.details.join('\n'), contains('schemaVersion must be 2'));
      }
    });

    test('rejects an unknown top-level key', () async {
      final manifest = V2RegistryFixture.buildManifest();
      manifest['surprise'] = true;
      fixture.writeManifest(manifest);
      expect(
        RegistryManifestLoader(LocalRegistrySource(fixture.root)).load(),
        throwsA(isA<RegistryManifestException>()),
      );
    });

    test('accepts a manifest whose fileHashes omit themes/*.json', () async {
      // The generated kit manifest hashes only copyable files; the loader must
      // not require a digest for consumed preset JSON.
      final loaded =
          await RegistryManifestLoader(LocalRegistrySource(fixture.root))
              .load();
      expect(loaded.manifest.declaredFiles, isNotEmpty);
      expect(loaded.manifest.fileHashes.containsKey('themes/vercel.json'),
          isFalse);
    });
  });
}
