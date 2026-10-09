import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer_file_install_part.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/hashing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixtureRoot = p.absolute('test/fixtures/registry_v2');
  final reader = DirectoryRegistryFileReader(fixtureRoot);
  const installRoot = 'lib/ui/shadcn';
  const projectRoot = '/tmp/shadcn_project';

  InstallerFileInstaller installer() => InstallerFileInstaller(
        projectRoot: projectRoot,
        installRoot: installRoot,
        reader: reader,
      );

  group('targetPathFor', () {
    test('preserves the layer depth', () {
      final files = installer();
      expect(
        files.targetPathFor('foundation/data.dart'),
        '$installRoot/foundation/data.dart',
      );
      expect(
        files.targetPathFor('theme/color_utils.dart'),
        '$installRoot/theme/color_utils.dart',
      );
      expect(
        files.targetPathFor('primitives/form_core/form_core.dart'),
        '$installRoot/primitives/form_core/form_core.dart',
      );
    });

    test('preserves the components depth', () {
      expect(
        installer().targetPathFor('components/button/button.dart'),
        '$installRoot/components/button/button.dart',
      );
    });

    test('rejects a theme preset JSON', () {
      expect(
        () => installer().targetPathFor('themes/modern-minimal.json'),
        throwsArgumentError,
      );
    });
  });

  group('DirectoryRegistryFileReader', () {
    test('reads declared files and reports missing ones', () async {
      expect(await reader.readBytes('foundation/data.dart'), isNotNull);
      expect(await reader.readBytes('nope.dart'), isNull);
      expect(
        await reader.readString('theme/color_utils.dart'),
        contains('hex'),
      );
    });
  });

  group('import guard', () {
    test('accepts every fixture file', () async {
      final sources = await installer().readAll(const [
        'components/button/button.dart',
        'components/button/button_style.dart',
        'components/text_area/text_area.dart',
        'primitives/form_core/form_core.dart',
        'theme/color_tokens.dart',
      ]);
      final contents = {
        for (final entry in sources.entries)
          entry.key: decodeRegistryText(entry.value),
      };
      expect(() => installer().assertImportGuard(contents), returnsNormally);
    });

    test('rejects an import that escapes the layout', () {
      final contents = {
        'components/button/button.dart':
            "import '../../../foundation/data.dart';\n",
      };
      expect(
        () => installer().assertImportGuard(contents),
        throwsA(
          isA<ImportGuardException>()
              .having((e) => e.file, 'file', 'components/button/button.dart')
              .having(
                (e) => e.importTarget,
                'importTarget',
                '../../../foundation/data.dart',
              ),
        ),
      );
    });

    test('rejects an absolute import path', () {
      final contents = {
        'foundation/data.dart': "import '/etc/passwd.dart';\n",
      };
      expect(
        () => installer().assertImportGuard(contents),
        throwsA(isA<ImportGuardException>()),
      );
    });

    test('ignores dart: and package: imports', () {
      final contents = {
        'foundation/data.dart':
            "import 'dart:async';\nimport 'package:flutter/widgets.dart';\n",
      };
      expect(() => installer().assertImportGuard(contents), returnsNormally);
    });
  });

  group('readAll', () {
    test('throws for a declared-but-missing file', () {
      expect(
        () => installer().readAll(const ['foundation/missing.dart']),
        throwsA(isA<RegistryFileMissingException>()),
      );
    });
  });

  group('write', () {
    test('writes bytes, creates parents and returns the digest', () async {
      final temp = Directory.systemTemp.createTempSync('file_install_');
      addTearDown(() => temp.delete(recursive: true));
      final files = InstallerFileInstaller(
        projectRoot: temp.path,
        installRoot: installRoot,
        reader: reader,
      );
      final bytes = [104, 105];
      final installed = await files.write(
        source: 'foundation/data.dart',
        target: '$installRoot/foundation/data.dart',
        bytes: bytes,
      );
      final target = File(p.join(temp.path, installed.target));
      expect(await target.readAsBytes(), bytes);
      expect(installed.sha256, FileHashing.ofBytes(bytes));
    });
  });
}
