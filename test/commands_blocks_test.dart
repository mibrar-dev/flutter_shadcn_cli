import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/add_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/dry_run_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/info_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/list_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/remove_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/search_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/update_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands_doctor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/v2_registry_fixture.dart';

/// The user-facing side of the blocks layer (P6-B2): `add <block>`,
/// `list --blocks`, `list --category`, `search`, `info <block>`, `update` and
/// `doctor`.
void main() {
  group('blocks commands', () {
    late V2RegistryFixture fixture;
    late Directory project;

    setUp(() {
      fixture = V2RegistryFixture.create();
      project = Directory.systemTemp.createTempSync('blocks_commands_app_');
      File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync(
        'name: blocks_app\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
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

    /// Captures `stdout.writeln` (the human output), `print` (the JSON
    /// envelope) and stderr (the error line), because the catalog commands
    /// write to all three.
    Future<({int code, String out})> capture(
      Future<int> Function() run,
    ) async {
      final buffer = StringBuffer();
      final out = _RecordingSink((line) => buffer.writeln(line));
      final err = _RecordingSink((line) => buffer.writeln(line));
      final code = await runZoned(
        () => IOOverrides.runZoned(run, stdout: () => out, stderr: () => err),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => buffer.writeln(line),
        ),
      );
      return (code: code, out: buffer.toString());
    }

    Future<({int code, String out})> add(List<String> args) => capture(
          () => runAddCommand(
            addCommand: parse(['add', ...args]).command,
            rootArgs: parse(['add', ...args]).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ),
        );

    Future<({int code, String out})> runList(List<String> args) => capture(
          () => runListCommand(
            listCommand: parse(['list', ...args]).command,
            rootArgs: parse(['list', ...args]).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ),
        );

    String file(String rel) => p.join(project.path, rel);
    bool exists(String rel) => File(file(rel)).existsSync();

    Map<String, dynamic> jsonOf(String out) =>
        jsonDecode(out) as Map<String, dynamic>;

    Map<String, dynamic> lock() =>
        jsonDecode(File(file('shadcn.lock')).readAsStringSync())
            as Map<String, dynamic>;

    test('add installs a block with its components', () async {
      final result = await add(['login-01']);
      expect(result.code, ExitCodes.success);
      expect(exists('lib/ui/shadcn/blocks/login-01/login_01.dart'), isTrue);
      expect(exists('lib/ui/shadcn/components/button/button.dart'), isTrue);
      final blocks = lock()['blocks'] as List;
      expect(blocks, hasLength(1));
      final block = blocks.single as Map<String, dynamic>;
      expect(block['id'], 'login-01');
      expect(
        (block['files'] as Map).keys.single,
        'lib/ui/shadcn/blocks/login-01/login_01.dart',
      );
      expect((block['deps'] as Map)['components'], ['button']);
      // The lock stays v2 and still records the components the block pulled.
      expect(lock()['lockfileVersion'], 2);
      expect(
        [
          for (final entry in lock()['components'] as List)
            (entry as Map)['id'],
        ],
        ['button'],
      );
    });

    test('add --dry-run plans the block without writing', () async {
      final result = await add(['login-01', '--dry-run', '--json']);
      expect(result.code, ExitCodes.success);
      final plan = (jsonOf(result.out)['data'] as Map)['plan'] as Map;
      expect(plan['blocks'], ['login-01']);
      expect(plan['components'], ['button']);
      expect(exists('lib/ui/shadcn/blocks/login-01/login_01.dart'), isFalse);
    });

    test('dry-run command resolves a block too', () async {
      final args = parse(['dry-run', 'login-01', '--json']);
      final result = await capture(() => runDryRunCommand(
            dryRunCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.success);
      expect((jsonOf(result.out)['data'] as Map)['blocks'], ['login-01']);
    });

    test('an unknown id still exits 30', () async {
      final result = await add(['nope-01']);
      expect(result.code, ExitCodes.componentMissing);
      expect(result.out, contains('Unknown component or block id "nope-01"'));
    });

    test('list groups components by category and lists blocks separately',
        () async {
      final components = await runList(['--json']);
      final data = (jsonOf(components.out)['data'] as Map);
      expect(data['kind'], 'component');
      expect(
        [
          for (final entry in data['components'] as List)
            (entry as Map)['category'],
        ],
        everyElement('core'),
      );
      expect(data['blocks'], isEmpty);

      final blocks = await runList(['--blocks', '--json']);
      final blockData = (jsonOf(blocks.out)['data'] as Map);
      expect(blockData['kind'], 'block');
      expect(blockData['count'], 1);
      final block = (blockData['blocks'] as List).single as Map;
      expect(block['id'], 'login-01');
      expect(block['category'], 'Authentication');
      expect(block['viewport'], 'desktop');
      expect(blockData['components'], isEmpty);
    });

    test('list --category filters the catalog', () async {
      final hit = await runList(['--blocks', '--category', 'authentication']);
      expect(hit.code, ExitCodes.success);
      expect(hit.out, contains('login-01'));
      expect(hit.out, contains('Authentication (1):'));
      expect(hit.out, contains('[desktop]'));

      final miss = await runList(['--category', 'Nope']);
      expect(miss.out, contains('No components in category "Nope"'));

      final filtered = await runList(['--category', 'core', '--json']);
      final data = (jsonOf(filtered.out)['data'] as Map);
      expect(data['count'], 2);
      expect(
        [
          for (final entry in data['components'] as List)
            (entry as Map)['category'],
        ],
        everyElement('core'),
      );
    });

    test('search finds a block and reports its kind', () async {
      final args = parse(['search', 'login', '--json']);
      final result = await capture(() => runSearchCommand(
            searchCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      final data = (jsonOf(result.out)['data'] as Map);
      expect(data['count'], 1);
      final match = (data['blocks'] as List).single as Map;
      expect(match['id'], 'login-01');
      expect(match['kind'], 'block');
      expect(match['category'], 'Authentication');
    });

    test('info resolves a block and a component', () async {
      final block = await capture(() => runInfoCommand(
            infoCommand: parse(['info', 'login-01', '--json']).command,
            rootArgs: parse(['info', 'login-01', '--json']).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      final blockData = jsonOf(block.out)['data'] as Map;
      expect(blockData['kind'], 'block');
      expect(blockData['viewport'], 'desktop');
      expect(blockData['install'], 'flutter_shadcn add login-01');
      expect(
        blockData['import'],
        'package:<your_app>/lib/ui/shadcn/blocks/login-01/login_01.dart',
      );
      expect((blockData['closure'] as Map)['components'], ['button']);

      final component = await capture(() => runInfoCommand(
            infoCommand: parse(['info', 'button', '--json']).command,
            rootArgs: parse(['info', 'button', '--json']).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      final componentData = jsonOf(component.out)['data'] as Map;
      expect(componentData['kind'], 'component');
      expect(componentData['category'], 'core');
    });

    test('info for an unknown id exits 30', () async {
      final result = await capture(() => runInfoCommand(
            infoCommand: parse(['info', 'nope-01', '--json']).command,
            rootArgs: parse(['info', 'nope-01', '--json']).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.componentMissing);
    });

    test('update refreshes an installed block', () async {
      await add(['login-01']);
      fixture.writeRegistryFile(
        'blocks/login-01/login_01.dart',
        'class Login01 { final v = 2; }\n',
      );
      final report = await capture(() => runUpdateCommand(
            updateCommand: parse(['update', '--json']).command,
            rootArgs: parse(['update', '--json']).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      final data = (jsonOf(report.out)['data'] as Map);
      expect(
        data['updated'],
        contains('lib/ui/shadcn/blocks/login-01/login_01.dart'),
      );
      expect(
        File(file('lib/ui/shadcn/blocks/login-01/login_01.dart'))
            .readAsStringSync(),
        contains('v = 2'),
      );
    });

    test('update leaves an edited block file alone', () async {
      await add(['login-01']);
      File(file('lib/ui/shadcn/blocks/login-01/login_01.dart'))
          .writeAsStringSync('class Login01 { final mine = true; }\n');
      final report = await capture(() => runUpdateCommand(
            updateCommand: parse(['update', '--json']).command,
            rootArgs: parse(['update', '--json']).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      final data = (jsonOf(report.out)['data'] as Map);
      expect(
        data['modified'],
        contains('lib/ui/shadcn/blocks/login-01/login_01.dart'),
      );
      expect(
        File(file('lib/ui/shadcn/blocks/login-01/login_01.dart'))
            .readAsStringSync(),
        contains('mine = true'),
      );
    });

    test('doctor is clean with a block installed', () async {
      await add(['login-01']);
      final result = await capture(() => runDoctorCommand(
            doctorCommand: parse(['doctor', '--json']).command,
            rootArgs: parse(['doctor', '--json']).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, DoctorExit.clean);
      expect((jsonOf(result.out)['data'] as Map)['errors'], isEmpty);
    });

    test('remove --all clears the components and the blocks together',
        () async {
      await add(['login-01']);
      final result = await capture(
        () => runRemoveCommand(
          removeCommand: parse(['remove', '--all', '--json']).command,
          rootArgs: parse(['remove', '--all', '--json']).root,
          projectRoot: project.path,
          registryOverride: fixture.root,
        ),
      );
      expect(result.code, ExitCodes.success);
      expect(exists('lib/ui/shadcn/blocks/login-01/login_01.dart'), isFalse);
      expect(exists('lib/ui/shadcn/components/button/button.dart'), isFalse);
      final lock = jsonDecode(File(file('shadcn.lock')).readAsStringSync())
          as Map<String, dynamic>;
      expect(lock['blocks'], isEmpty);
      expect(lock['components'], isEmpty);
    });

    test('remove deletes the block files and keeps its components', () async {
      await add(['login-01']);
      final result = await capture(() => runRemoveCommand(
            removeCommand: parse(['remove', 'login-01', '--json']).command,
            rootArgs: parse(['remove', 'login-01', '--json']).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.success);
      expect(exists('lib/ui/shadcn/blocks/login-01/login_01.dart'), isFalse);
      expect(exists('lib/ui/shadcn/components/button/button.dart'), isTrue);
      expect(lock()['blocks'], isEmpty);
    });
  });
}

/// Minimal [Stdout] stand-in: the catalog commands write human output through
/// `stdout.writeln`, so the test has to record the sink, not just `print`.
class _RecordingSink implements Stdout {
  _RecordingSink(this.onLine);

  final void Function(String line) onLine;

  @override
  Encoding encoding = utf8;

  void _record(Object? object) {
    if (object == null) return;
    final text = '$object';
    if (text.isEmpty) return;
    onLine(text.endsWith('\n') ? text.substring(0, text.length - 1) : text);
  }

  @override
  Future<void> get done => Future<void>.value();

  @override
  bool get hasTerminal => false;

  @override
  IOSink get nonBlocking => this;

  @override
  bool get supportsAnsiEscapes => false;

  @override
  int get terminalColumns => 80;

  @override
  int get terminalLines => 24;

  @override
  String get lineTerminator => '\n';

  @override
  set lineTerminator(String value) {
    if (value != '\n') throw ArgumentError.value(value, 'lineTerminator');
  }

  @override
  void add(List<int> data) => _record(encoding.decode(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(add);

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  @override
  void write(Object? object) => _record(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {
    objects.forEach(_record);
  }

  @override
  void writeCharCode(int charCode) => _record(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => _record('$object\n');
}
