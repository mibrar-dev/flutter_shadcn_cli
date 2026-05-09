import 'dart:io';

import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/deps_command.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('runDepsCommand', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('deps_command_');
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('matches sdk dependency shorthand against pubspec map syntax',
        () async {
      await File(p.join(tempRoot.path, 'pubspec.yaml')).writeAsString(
        [
          'name: deps_test',
          'dependencies:',
          '  flutter:',
          '    sdk: flutter',
          '  flutter_localizations:',
          '    sdk: flutter',
        ].join('\n'),
      );

      final registry = Registry(
        {
          'components': [
            {
              'id': 'button',
              'name': 'Button',
              'files': const [],
              'pubspec': {
                'dependencies': {
                  'flutter_localizations': 'sdk: flutter',
                },
              },
            },
          ],
        },
        RegistryLocation.local(tempRoot.path),
        RegistryLocation.local(tempRoot.path),
      );

      final exitCode = await runDepsCommand(
        registry: registry,
        targetDir: tempRoot.path,
        config: const ShadcnConfig(),
        includeAll: true,
        jsonOutput: false,
        logger: CliLogger(useColor: false),
      );

      expect(exitCode, ExitCodes.success);
    });
  });
}
