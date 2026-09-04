import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer_file_writer_service.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('InstallerFileWriterService', () {
    late Directory tempDir;
    late Directory registryDir;
    late Directory projectDir;
    late InstallerFileWriterService service;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('installer_file_writer_');
      registryDir = Directory(p.join(tempDir.path, 'registry'))
        ..createSync(recursive: true);
      projectDir = Directory(p.join(tempDir.path, 'project'))
        ..createSync(recursive: true);
      File(p.join(registryDir.path, 'components/button.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('class Button {}\n');
      final registry = Registry(
        const {'components': []},
        RegistryLocation.local(registryDir.path),
        RegistryLocation.local(registryDir.path),
      );
      service = InstallerFileWriterService(
        registry: registry,
        logger: CliLogger(),
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('writes registry bytes to destination and creates parents', () async {
      final destination = p.join(projectDir.path, 'lib/ui/button.dart');

      await service.writeRegistryFile(
        file: RegistryFile(
          source: 'components/button.dart',
          destination: 'lib/ui/button.dart',
        ),
        destinationPath: destination,
        shouldInstall: true,
      );

      expect(File(destination).readAsStringSync(), 'class Button {}\n');
    });

    test('skips optional file without reading registry source', () async {
      final destination =
          p.join(projectDir.path, 'lib/ui/missing_preview.dart');

      await service.writeRegistryFile(
        file: RegistryFile(
          source: 'components/missing_preview.dart',
          destination: 'lib/ui/missing_preview.dart',
        ),
        destinationPath: destination,
        shouldInstall: false,
      );

      expect(File(destination).existsSync(), isFalse);
    });
  });
}
