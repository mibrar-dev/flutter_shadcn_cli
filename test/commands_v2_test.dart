import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/add_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/audit_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/info_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/init_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/list_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/remove_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/search_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/update_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/validate_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands_doctor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/v2_registry_fixture.dart';

void main() {
  group('v2 commands', () {
    late V2RegistryFixture fixture;
    late Directory project;

    setUp(() {
      fixture = V2RegistryFixture.create();
      project = Directory.systemTemp.createTempSync('commands_v2_app_');
      File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync(
        'name: commands_app\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
      );
    });

    tearDown(() {
      fixture.dispose();
      project.deleteSync(recursive: true);
    });

    ({ArgResults root, ArgResults command}) parse(List<String> args) {
      final results = buildCliParser()
          .parse(normalizeCliArgs(['--registry', fixture.root, ...args]));
      return (root: results, command: results.command!);
    }

    Future<({int code, String out})> capture(Future<int> Function() run) async {
      final buffer = StringBuffer();
      final code = await runZoned(
        run,
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => buffer.writeln(line),
        ),
      );
      return (code: code, out: buffer.toString());
    }

    String file(String rel) => p.join(project.path, rel);
    bool exists(String rel) => File(file(rel)).existsSync();

    test('add installs the closure and writes the lock', () async {
      final args = parse(['add', 'button', '--json']);
      final result = await capture(() => runAddCommand(
            addCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));

      expect(result.code, ExitCodes.success);
      expect(exists('lib/ui/shadcn/components/button/button.dart'), isTrue);
      expect(
          exists('lib/ui/shadcn/components/button/button_theme.dart'), isTrue);
      expect(exists('lib/ui/shadcn/foundation/data.dart'), isTrue);
      expect(exists('shadcn.lock'), isTrue);
      final json = jsonDecode(result.out) as Map<String, dynamic>;
      expect((json['data'] as Map)['plan']['components'], ['button']);
    });

    test('add input pulls the component dependency too', () async {
      final args = parse(['add', 'input', '--json']);
      await capture(() => runAddCommand(
            addCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(exists('lib/ui/shadcn/components/input/input.dart'), isTrue);
      expect(exists('lib/ui/shadcn/components/button/button.dart'), isTrue);
    });

    test('add --dry-run writes nothing', () async {
      final args = parse(['add', 'button', '--dry-run']);
      final result = await capture(() => runAddCommand(
            addCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.success);
      expect(exists('lib/ui/shadcn/components/button/button.dart'), isFalse);
    });

    test('add an unknown component exits 30', () async {
      final args = parse(['add', 'nope', '--json']);
      final result = await capture(() => runAddCommand(
            addCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.componentMissing);
    });

    test('list reports both components', () async {
      final args = parse(['list', '--json']);
      final result = await capture(() => runListCommand(
            listCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      final json = jsonDecode(result.out) as Map<String, dynamic>;
      final ids = [
        for (final item in (json['data'] as Map)['components'] as List)
          (item as Map)['id'],
      ];
      expect(ids, ['button', 'input']);
    });

    test('search matches by tag', () async {
      final args = parse(['search', 'form', '--json']);
      final result = await capture(() => runSearchCommand(
            searchCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      final json = jsonDecode(result.out) as Map<String, dynamic>;
      expect((json['data'] as Map)['count'], 1);
      expect(
        ((json['data'] as Map)['components'] as List).first,
        containsPair('id', 'input'),
      );
    });

    test('info shows the closure and import path', () async {
      final args = parse(['info', 'input', '--json']);
      final result = await capture(() => runInfoCommand(
            infoCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      final data =
          (jsonDecode(result.out) as Map<String, dynamic>)['data'] as Map;
      expect((data['closure'] as Map)['components'], ['button', 'input']);
      expect(data['import'],
          'package:<your_app>/lib/ui/shadcn/components/input/input.dart');
    });

    test('info for an unknown component exits 30', () async {
      final args = parse(['info', 'nope', '--json']);
      final result = await capture(() => runInfoCommand(
            infoCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.componentMissing);
    });

    test('remove deletes registry files and keeps the user theme', () async {
      await capture(() => runAddCommand(
            addCommand: parse(['add', 'button']).command,
            rootArgs: parse(['add', 'button']).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      final args = parse(['remove', 'button', '--json']);
      final result = await capture(() => runRemoveCommand(
            removeCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.success);
      expect(exists('lib/ui/shadcn/components/button/button.dart'), isFalse);
      expect(
          exists('lib/ui/shadcn/components/button/button_theme.dart'), isTrue);
    });

    test('remove refuses a component a dependent still needs', () async {
      await capture(() => runAddCommand(
            addCommand: parse(['add', 'input']).command,
            rootArgs: parse(['add', 'input']).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      final args = parse(['remove', 'button', '--json']);
      final result = await capture(() => runRemoveCommand(
            removeCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.success);
      expect(exists('lib/ui/shadcn/components/button/button.dart'), isTrue);
    });

    test('init installs the core and generates app_theme.dart', () async {
      final args = parse(['init', '--theme', 'vercel', '--json']);
      final result = await capture(() => runInitCommand(
            initCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.success);
      expect(exists('lib/ui/shadcn/foundation/data.dart'), isTrue);
      expect(exists('lib/ui/shadcn/theme/app_theme.dart'), isTrue);
      expect(exists('.shadcn/config.json'), isTrue);
      expect(exists('shadcn.lock'), isTrue);
    });

    test('doctor is clean after init', () async {
      await capture(() => runInitCommand(
            initCommand: parse(['init', '--theme', 'vercel']).command,
            rootArgs: parse(['init', '--theme', 'vercel']).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      final args = parse(['doctor', '--json']);
      final result = await capture(() => runDoctorCommand(
            doctorCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, DoctorExit.clean);
    });

    test('validate accepts the manifest', () async {
      final args = parse(['validate', '--json']);
      final result = await capture(() => runValidateCommandCli(
            command: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.success);
    });

    test('audit reports drift after a registry-owned file is edited', () async {
      await capture(() => runAddCommand(
            addCommand: parse(['add', 'button']).command,
            rootArgs: parse(['add', 'button']).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      File(file('lib/ui/shadcn/components/button/button.dart'))
          .writeAsStringSync('class Button { final mine = true; }\n');
      final args = parse(['audit', '--json']);
      final result = await capture(() => runAuditCommandCli(
            command: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.validationFailed);
    });

    test('update --check exits 1 when the registry moved on', () async {
      await capture(() => runAddCommand(
            addCommand: parse(['add', 'button']).command,
            rootArgs: parse(['add', 'button']).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      fixture.writeRegistryFile(
        'components/button/button.dart',
        'class Button { final v = 2; }\n',
      );
      final args = parse(['update', '--check', '--json']);
      final result = await capture(() => runUpdateCommand(
            updateCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, 1);
    });
  });
}
