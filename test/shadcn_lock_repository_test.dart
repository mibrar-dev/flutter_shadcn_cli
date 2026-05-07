import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ShadcnLockRepository', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('shadcn_lock_test_');
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('synthesizes legacy component manifests when lockfile is missing',
        () async {
      final manifestDir = Directory(
        p.join(tempRoot.path, '.shadcn', 'components'),
      )..createSync(recursive: true);
      File(p.join(manifestDir.path, 'button.json')).writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'id': 'button',
          'version': '1.0.0',
          'files': ['registry/components/button/button.dart'],
          'registryRoot': '/tmp/registry',
        }),
      );

      final lock = await ShadcnLockRepository(
        tempRoot.path,
      ).loadOrSynthesize();

      expect(lock.lockfileVersion, 1);
      expect(lock.registries['shadcn']?.registryRoot, '/tmp/registry');
      expect(lock.components, hasLength(1));
      expect(lock.components.single.qualifiedId, '@shadcn/button');
      expect(lock.components.single.version, '1.0.0');
      expect(
        lock.components.single.installedFiles,
        ['lib/ui/shadcn/components/button/button.dart'],
      );
    });
  });
}
