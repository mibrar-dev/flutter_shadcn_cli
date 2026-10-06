import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/installer.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';

void main() {
  group('generateAliases barrel', () {
    late Directory tempRoot;
    late Directory targetRoot;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('shadcn_alias_');
      targetRoot = Directory(p.join(tempRoot.path, 'app'))..createSync();
      await ShadcnConfig.save(
        targetRoot.path,
        const ShadcnConfig(
          installPath: 'lib/ui/shadcn',
          sharedPath: 'lib/ui/shadcn/shared',
        ),
      );
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    Future<String> generateBarrel({
      required Map<String, String> components,
      List<String>? logLines,
    }) async {
      for (final entry in components.entries) {
        final dir = Directory(
          p.join(
            targetRoot.path, 'lib', 'ui', 'shadcn', 'components', entry.key),
        )..createSync(recursive: true);
        File(p.join(dir.path, '${entry.key}.dart'))
            .writeAsStringSync(entry.value);
      }
      final lines = logLines ?? <String>[];
      final installer = Installer(
        registry: Registry(
          const {},
          RegistryLocation.local(tempRoot.path),
          RegistryLocation.local(tempRoot.path),
        ),
        targetDir: targetRoot.path,
        logger: CliLogger(
          useColor: false,
          writeLine: lines.add,
          writeStderrLine: lines.add,
        ),
      );
      await installer.generateAliases();
      return File(
        p.join(targetRoot.path, 'lib', 'ui', 'shadcn', 'app_components.dart'),
      ).readAsStringSync();
    }

    test('hides duplicate declarations on later exports', () async {
      final lines = <String>[];
      final barrel = await generateBarrel(
        logLines: lines,
        components: {
          // Alphabetically first: wins the names.
          'aaa': '''
class Shared {}
enum DupEnum { a }
typedef DupFn = void Function();
class OnlyAaa {}
''',
          'zzz': '''
class Shared {}
enum DupEnum { a }
typedef DupFn = void Function();
class OnlyZzz {}
''',
        },
      );

      expect(barrel, contains("export 'components/aaa/aaa.dart';"));
      expect(
        barrel,
        contains("export 'components/zzz/zzz.dart' hide DupEnum, DupFn, Shared;"),
      );
      expect(lines.any((line) => line.contains('Duplicate declaration "Shared"')), isTrue);
      expect(lines.any((line) => line.contains('Duplicate declaration "DupEnum"')), isTrue);
      expect(lines.any((line) => line.contains('Duplicate declaration "DupFn"')), isTrue);
    });

    test('follows exports when collecting declarations', () async {
      final lines = <String>[];
      final firstComponents = <String, String>{
        'aam': '''
export 'src/impl.dart';

class AamOwn {}
''',
      };
      // Write the exported impl file manually: components whose main file
      // exports (rather than parts) their implementation, like button.
      final implDir = Directory(
        p.join(
          targetRoot.path, 'lib', 'ui', 'shadcn', 'components', 'aam', 'src'),
      )..createSync(recursive: true);
      File(p.join(implDir.path, 'impl.dart')).writeAsStringSync('''
class SharedViaExport {}
class IconButton {}
''');
      final barrel = await generateBarrel(
        logLines: lines,
        components: {
          ...firstComponents,
          'zzm': '''
class SharedViaExport {}
''',
        },
      );

      expect(
        barrel,
        contains(
          "export 'components/zzm/zzm.dart' hide SharedViaExport;"),
      );
      expect(barrel, contains('IconButton'));
      expect(
        lines.any(
          (line) => line.contains('Duplicate declaration "SharedViaExport"')),
        isTrue,
      );
    });

    test('ignores declarations in foreign part-of files', () async {
      final partDir = Directory(
        p.join(
          targetRoot.path, 'lib', 'ui', 'shadcn', 'components', 'aam2', 'src'),
      )..createSync(recursive: true);
      File(p.join(partDir.path, 'foreign.dart')).writeAsStringSync('''
part of some.other.library;

// Would trigger a material hide if wrongly attributed to aam2.
class BadgeTheme {}
''');
      final barrel = await generateBarrel(
        components: {
          'aam2': '''
part 'src/foreign.dart';

class Real {}
''',
        },
      );

      expect(
        barrel,
        contains("export 'components/aam2/aam2.dart';"),
      );
      expect(barrel, isNot(contains('material.dart')));
      expect(barrel, isNot(contains('BadgeTheme')));
    });

    test('hides material-colliding names incl BadgeTheme with valid syntax',
        () async {
      final barrel = await generateBarrel(
        components: {
          'badge': '''
class BadgeTheme {}
class ShadcnBadge {}
''',
        },
      );

      expect(
        barrel,
        contains("export 'package:flutter/material.dart' hide"),
      );
      expect(barrel, contains('BadgeTheme'));
      expect(barrel, isNot(contains('ShadcnBadge, exclusively')));

      // Every line of the material hide block ends with ',' except the
      // terminator, which ends with ';'. A missing comma misparses all
      // following exports, so lock the syntax here.
      final barrelLines = barrel.split('\n');
      final hideStart =
          barrelLines.indexWhere((line) => line.contains('material.dart') && line.contains('hide'));
      expect(hideStart, isNot(-1));
      var i = hideStart + 1;
      var sawTerminator = false;
      while (i < barrelLines.length) {
        final line = barrelLines[i].trim();
        i += 1;
        if (line.isEmpty) {
          break;
        }
        if (line.endsWith(';')) {
          sawTerminator = true;
          break;
        }
        expect(line.endsWith(','), isTrue, reason: 'hide entry without comma: $line');
      }
      expect(sawTerminator, isTrue);
    });

    test('hides component showDialog colliding with material', () async {
      final lines = <String>[];
      final barrel = await generateBarrel(
        logLines: lines,
        components: {
          'dialog': '''
/// Use [showDialog] instead.
Future<T?> showDialog<T>({Object? arguments}) async => null;

class DialogHelper {
  Future<void> open() async {
    await showDialog(arguments: null);
  }
}
''',
        },
      );

      expect(
        barrel,
        contains("export 'components/dialog/dialog.dart' hide showDialog;"),
      );
      expect(
        lines.any((line) => line.contains('Duplicate declaration "showDialog"')),
        isTrue,
      );
    });

    test('does not mistake doc references or call sites for declarations',
        () async {
      final lines = <String>[];
      final barrel = await generateBarrel(
        logLines: lines,
        components: {
          'helper': '''
/// See [showDialog] for details.
class Helper {
  Future<void> open() async {
    await showDialog();
  }
}
''',
        },
      );

      expect(
        barrel,
        contains("export 'components/helper/helper.dart';"),
      );
      expect(
        lines.any((line) => line.contains('Duplicate declaration "showDialog"')),
        isFalse,
      );
    });
  });
}
