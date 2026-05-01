import 'dart:io';

import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/multi_registry_manager.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/bootstrap_support.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/info_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/remove_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/registry_bootstrap_exception.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/runtime_roots.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('component address command boundaries', () {
    late Directory tempRoot;
    late MultiRegistryManager multiRegistry;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('shadcn_address_cmd_');
      multiRegistry = MultiRegistryManager(
        targetDir: tempRoot.path,
        offline: true,
        logger: CliLogger(),
      );
    });

    tearDown(() {
      multiRegistry.close();
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('info rejects malformed qualified component refs before lookup',
        () async {
      final rootArgs = buildCliParser().parse([
        '--offline',
        'info',
        '@shadcn/button/extra',
      ]);

      final exitCode = await runInfoCommand(
        infoCommand: rootArgs.command!,
        rootArgs: rootArgs,
        localRegistryRoot: p.join(tempRoot.path, 'missing-registry'),
        cliRoot: null,
        config: const ShadcnConfig(),
        offline: true,
        logger: CliLogger(),
      );

      expect(exitCode, ExitCodes.usage);
    });

    test('remove rejects malformed qualified component refs before installer',
        () async {
      for (final token in ['shadcn:', '@shadcn']) {
        final rootArgs = buildCliParser().parse([
          '--offline',
          'remove',
          token,
        ]);

        final exitCode = await runRemoveCommand(
          removeCommand: rootArgs.command!,
          installer: null,
          multiRegistry: multiRegistry,
          rootArgs: rootArgs,
          config: const ShadcnConfig(),
          preloadedNamespace: null,
          logger: CliLogger(),
        );

        expect(exitCode, ExitCodes.usage, reason: token);
      }
    });

    test('remove rejects malformed refs before registry preload', () async {
      final rootArgs = buildCliParser().parse([
        '--offline',
        'remove',
        '@shadcn',
      ]);

      await expectLater(
        () => preloadRegistryIfNeeded(
          argResults: rootArgs,
          roots: const ResolvedRoots(localRegistryRoot: null, cliRoot: null),
          config: const ShadcnConfig(),
          offline: true,
          routeInitToMultiRegistry: false,
          routeAddToMultiRegistry: false,
          namespaceOverride: null,
          logger: CliLogger(),
        ),
        throwsA(
          isA<RegistryBootstrapException>()
              .having(
                (error) => error.message,
                'message',
                contains('Invalid component address'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('@namespace/component'),
              )
              .having(
                (error) => error.exitCode(),
                'exitCode',
                ExitCodes.usage,
              ),
        ),
      );
    });
  });
}
