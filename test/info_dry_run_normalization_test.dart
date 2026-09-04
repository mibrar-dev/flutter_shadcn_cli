import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/index/index_component.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/multi_registry_manager.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/dry_run_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/info_command.dart';
import 'package:test/test.dart';

IndexComponent _component({
  String import = '',
  String importPath = '',
}) {
  return IndexComponent.fromJson({
    'id': 'button',
    'name': 'Button',
    'category': 'control',
    'description': 'd',
    'import': import,
    'importPath': importPath,
  });
}

void main() {
  group('IndexComponent import normalization (info --json importPath)', () {
    test('inserts missing components segment into importPath', () {
      final comp = _component(
        importPath: 'ui/shadcn/control/button/button.dart',
      );
      expect(
        comp.importPath,
        'ui/shadcn/components/control/button/button.dart',
      );
    });

    test('inserts missing components segment into import statement', () {
      final comp = _component(
        import:
            "import 'package:<your_app>/ui/shadcn/control/button/button.dart';",
      );
      expect(
        comp.import_,
        "import 'package:<your_app>/ui/shadcn/components/control/button/button.dart';",
      );
    });

    test('leaves already-correct paths untouched (idempotent)', () {
      const importPath = 'ui/shadcn/components/control/button/button.dart';
      const import =
          "import 'package:<your_app>/ui/shadcn/components/control/button/button.dart';";
      final comp = _component(import: import, importPath: importPath);
      expect(comp.importPath, importPath);
      expect(comp.import_, import);
    });

    test('leaves empty and foreign paths untouched', () {
      expect(IndexComponent.normalizeImportPath(''), '');
      expect(
        IndexComponent.normalizeImportPath('ui/orient/control/foo/foo.dart'),
        'ui/orient/control/foo/foo.dart',
      );
      expect(
        IndexComponent.normalizeImportStatement('not an import'),
        'not an import',
      );
    });
  });

  group('dry-run component ref normalization', () {
    test('strips @namespace prefix identically to add/info', () {
      expect(normalizeDryRunComponentRef('@shadcn/button'), 'button');
      expect(normalizeDryRunComponentRef('button'), 'button');
      expect(
        normalizeDryRunComponentRef('@shadcn/button@1.0.0'),
        'button',
      );
    });

    test('passes malformed refs through for missing reporting', () {
      expect(normalizeDryRunComponentRef('@shadcn'), '@shadcn');
      expect(normalizeDryRunComponentRef(''), '');
    });
  });

  group('info rejects multiple components loudly', () {
    late Directory tempRoot;
    late MultiRegistryManager multiRegistry;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('shadcn_info_multi_');
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

    test('info A B --json returns usage error envelope (exit 2)', () async {
      final rootArgs = buildCliParser().parse(['info', 'a', 'b', '--json']);
      final lines = <String>[];
      final code = await runZoned(
        () => runInfoCommand(
          infoCommand: rootArgs.command!,
          multiRegistry: multiRegistry,
          logger: CliLogger(),
        ),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            lines.add(line);
          },
        ),
      );

      expect(code, ExitCodes.usage);
      final payload = jsonDecode(lines.join('\n')) as Map<String, dynamic>;
      expect(payload['status'], 'error');
      expect(payload['command'], 'info');
      final errors = payload['errors'] as List;
      expect(errors.single['code'], 'usage_error');
      expect(
        (errors.single['message'] as String),
        contains('a, b'),
      );
      expect(payload['meta']['exitCode'], ExitCodes.usage);
    });

    test('info A B (text) exits usage without answering the first',
        () async {
      final rootArgs = buildCliParser().parse(['info', 'a', 'b']);
      final code = await runInfoCommand(
        infoCommand: rootArgs.command!,
        multiRegistry: multiRegistry,
        logger: CliLogger(),
      );
      expect(code, ExitCodes.usage);
    });
  });
}
