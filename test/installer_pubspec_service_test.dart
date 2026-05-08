import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer_pubspec_service.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('InstallerPubspecService', () {
    late Directory tempDir;
    late InstallerPubspecService service;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pubspec_service_test_');
      service = InstallerPubspecService(
        targetDir: tempDir.path,
        logger: CliLogger(),
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('adds dependencies, assets, and fonts without duplicating entries',
        () async {
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: app
dependencies:
  flutter:
    sdk: flutter
flutter:
  assets:
    - assets/existing/
''');

      await service.updateDependencies({'gap': '^3.0.1'});
      await service.updateAssets(['assets/generated/', 'assets/existing/']);
      await service.updateFonts([
        FontEntry.fromJson({
          'family': 'Inter',
          'fonts': [
            {'asset': 'assets/fonts/Inter-Regular.ttf'},
          ],
        }),
      ]);

      final pubspec =
          File(p.join(tempDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('  gap: ^3.0.1'));
      expect(
        'assets/generated/'.allMatches(pubspec),
        hasLength(1),
      );
      expect('assets/existing/'.allMatches(pubspec), hasLength(1));
      expect(pubspec, contains('  fonts:'));
      expect(pubspec, contains('    - family: Inter'));
      expect(
        pubspec,
        contains('        - asset: assets/fonts/Inter-Regular.ttf'),
      );
    });

    test('preflight reports dependency conflicts without rewriting pubspec',
        () async {
      final pubspecFile = File(p.join(tempDir.path, 'pubspec.yaml'));
      pubspecFile.writeAsStringSync('''
name: app
dependencies:
  gap: ^2.0.0
''');

      expect(
        () => service.preflightDependencies({'gap': '^3.0.1'}),
        throwsA(
          predicate(
            (error) =>
                error.toString().contains('pubspec.yaml dependency conflict') &&
                error.toString().contains(
                      'gap existing ^2.0.0, requested ^3.0.1',
                    ),
          ),
        ),
      );
      expect(pubspecFile.readAsStringSync(), contains('  gap: ^2.0.0'));
      expect(pubspecFile.readAsStringSync(), isNot(contains('^3.0.1')));
    });
  });
}
