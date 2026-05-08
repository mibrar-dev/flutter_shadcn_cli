import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer_alias_generator_service.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_platform_instruction_service.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('InstallerPlatformInstructionService', () {
    late Directory targetRoot;

    setUp(() {
      targetRoot = Directory.systemTemp.createTempSync(
        'flutter_shadcn_platform_alias_test_',
      );
    });

    tearDown(() {
      if (targetRoot.existsSync()) {
        targetRoot.deleteSync(recursive: true);
      }
    });

    test('writes configured platform instruction sections once', () async {
      final service = InstallerPlatformInstructionService(
        targetDir: targetRoot.path,
        logger: CliLogger(),
      );
      final component = Component.fromJson({
        'id': 'camera',
        'name': 'Camera',
        'files': [],
        'platform': {
          'android': {
            'permissions': ['android.permission.CAMERA'],
          },
        },
      });
      const config = ShadcnConfig(
        platformTargets: {
          'android': {'permissions': '.shadcn/test/android-permissions.xml'},
        },
      );

      await service.applyPlatformInstructions(component, config);
      await service.applyPlatformInstructions(component, config);

      final output = File(
        p.join(targetRoot.path, '.shadcn', 'test', 'android-permissions.xml'),
      ).readAsStringSync();
      expect(
        'shadcn_flutter_cli:android:permissions:start'.allMatches(output),
        hasLength(1),
      );
      expect(output, contains('<!-- android.permission.CAMERA -->'));
    });
  });

  group('InstallerAliasGeneratorService', () {
    late Directory targetRoot;

    setUp(() {
      targetRoot = Directory.systemTemp.createTempSync(
        'flutter_shadcn_alias_test_',
      );
    });

    tearDown(() {
      if (targetRoot.existsSync()) {
        targetRoot.deleteSync(recursive: true);
      }
    });

    test('generates prefixed aliases for component classes and parts',
        () async {
      final buttonDir = Directory(
        p.join(targetRoot.path, 'lib', 'ui', 'shadcn', 'components', 'button'),
      )..createSync(recursive: true);
      File(p.join(buttonDir.path, 'button.dart')).writeAsStringSync('''
part 'button_part.dart';

class Button<T extends Object> {}
''');
      File(p.join(buttonDir.path, 'button_part.dart')).writeAsStringSync('''
class ButtonController {}
class _PrivateButton {}
''');

      final service = InstallerAliasGeneratorService(
        targetDir: targetRoot.path,
      );

      await service.generateAliases(
        installPath: 'lib/ui/shadcn',
        classPrefix: 'App',
      );

      final aliasFile = File(
        p.join(targetRoot.path, 'lib', 'ui', 'shadcn', 'app_components.dart'),
      ).readAsStringSync();
      expect(aliasFile, contains("import 'components/button/button.dart';"));
      expect(
        aliasFile,
        contains('typedef AppButton<T extends Object> = Button<T>;'),
      );
      expect(
        aliasFile,
        contains('typedef AppButtonController = ButtonController;'),
      );
      expect(aliasFile, isNot(contains('App_PrivateButton')));
    });
  });
}
