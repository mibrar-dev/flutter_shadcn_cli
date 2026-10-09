import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/theme_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The command is exercised through `ArgResults`, which is all it consumes.
/// The parser below mirrors what the CLI registers for `theme` plus the root
/// options the theme flow reads; the parser itself is owned by another batch.
ArgParser buildThemeParser() => ArgParser()
  ..addFlag('list', negatable: false)
  ..addFlag('refresh', negatable: false)
  ..addFlag('json', negatable: false)
  ..addOption('apply', abbr: 'a')
  ..addOption('apply-file')
  ..addOption('apply-url')
  ..addFlag('help', abbr: 'h', negatable: false)
  ..addCommand(
    'list',
    ArgParser()
      ..addFlag('json', negatable: false)
      ..addFlag('help', abbr: 'h', negatable: false),
  )
  ..addCommand(
    'apply',
    ArgParser()
      ..addFlag('refresh', negatable: false)
      ..addFlag('json', negatable: false)
      ..addFlag('help', abbr: 'h', negatable: false),
  )
  ..addCommand(
    'widget',
    ArgParser()
      ..addFlag('list', negatable: false)
      ..addFlag('help', abbr: 'h', negatable: false),
  );

ArgParser buildRootParser() => ArgParser()
  ..addFlag('verbose', abbr: 'v', negatable: false)
  ..addFlag('offline', negatable: false)
  ..addOption('registry-name')
  ..addOption('registry-path')
  ..addOption('registry-url');

void main() {
  final fixtureRoot =
      p.join(Directory.current.path, 'test', 'fixtures', 'theme_registry_v2');
  late Directory temp;
  late _Capture capture;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('theme_command_');
    capture = _Capture();
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  File themeFile() =>
      File(p.join(temp.path, 'lib', 'ui', 'shadcn', 'theme', 'app_theme.dart'));

  Future<int> run(List<String> themeArgs, {List<String>? rootArgs}) async {
    final root = buildRootParser().parse(
      rootArgs ?? <String>['--registry-path', fixtureRoot],
    );
    final command = buildThemeParser().parse(themeArgs);
    return capture.run(
      () => runThemeCommand(
        themeCommand: command,
        rootArgs: root,
        installer: null,
        registrySupportsTheme: null,
      ),
      projectRoot: temp.path,
    );
  }

  group('theme list', () {
    test('prints the manifest catalogue', () async {
      expect(await run(<String>['list']), ExitCodes.success);
      expect(capture.stdout, contains('Available theme presets (2)'));
      expect(capture.stdout, contains('vercel'));
      expect(capture.stdout, contains('claude'));
      expect(capture.stdout, contains('theme apply <preset>'));
    });

    test('--json emits a parseable catalogue and nothing else', () async {
      expect(await run(<String>['list', '--json']), ExitCodes.success);
      final payload = jsonDecode(capture.stdout.trim()) as Map<String, dynamic>;
      expect(payload['current'], isNull);
      final presets = payload['presets']! as List<dynamic>;
      expect(presets, hasLength(2));
      expect(
        (presets.first as Map<String, dynamic>)['id'],
        'claude',
      );
      expect(presets.first['modes'], <String>['light', 'dark']);
      expect(presets.first['current'], isFalse);
      expect(presets.first['file'], 'themes/claude.json');
    });

    test('the legacy --list flag still works', () async {
      expect(await run(<String>['--list']), ExitCodes.success);
      expect(capture.stdout, contains('Available theme presets (2)'));
    });
  });

  group('theme apply', () {
    test('writes app_theme.dart and reports it as JSON', () async {
      expect(
          await run(<String>['apply', 'vercel', '--json']), ExitCodes.success);
      final payload = jsonDecode(capture.stdout.trim()) as Map<String, dynamic>;
      final applied = payload['applied']! as Map<String, dynamic>;
      expect(applied['status'], 'created');
      expect(applied['presetId'], 'vercel');
      expect(applied['presetName'], 'Vercel');
      expect(applied['path'], 'lib/ui/shadcn/theme/app_theme.dart');
      expect(applied['source'], 'themes/vercel.json');
      expect(themeFile().readAsStringSync(),
          contains('ShadcnThemeData buildVercelTheme'));
    });

    test('a second apply is a no-op', () async {
      await run(<String>['apply', 'vercel']);
      capture.reset();
      expect(
          await run(<String>['apply', 'vercel', '--json']), ExitCodes.success);
      final applied = (jsonDecode(capture.stdout.trim())
          as Map<String, dynamic>)['applied']! as Map<String, dynamic>;
      expect(applied['status'], 'unchanged');
    });

    test('accepts the legacy --apply flag and a bare preset', () async {
      expect(await run(<String>['--apply', 'claude', '--json']),
          ExitCodes.success);
      expect(themeFile().readAsStringSync(),
          contains('ShadcnThemeData buildClaudeTheme'));

      capture.reset();
      expect(await run(<String>['vercel', '--json']), ExitCodes.success);
      final applied = (jsonDecode(capture.stdout.trim())
          as Map<String, dynamic>)['applied']! as Map<String, dynamic>;
      expect(applied['presetId'], 'vercel');
    });

    test('matches a preset by display name', () async {
      expect(
          await run(<String>['apply', 'Claude', '--json']), ExitCodes.success);
      expect(themeFile().readAsStringSync(),
          contains('ShadcnThemeData buildClaudeTheme'));
    });

    test('an unknown preset fails with exit code 50', () async {
      expect(await run(<String>['apply', 'nope']), ExitCodes.validationFailed);
      expect(themeFile().existsSync(), isFalse);
    });

    test('drift is reported and exits 50 without touching the file', () async {
      await run(<String>['apply', 'vercel']);
      themeFile().writeAsStringSync('// hand edited\n');

      expect(
          await run(<String>['apply', 'claude']), ExitCodes.validationFailed);
      expect(themeFile().readAsStringSync(), '// hand edited\n');
    });

    test('--refresh rewrites a drifted file', () async {
      await run(<String>['apply', 'vercel']);
      themeFile().writeAsStringSync('// hand edited\n');

      expect(
        await run(<String>['apply', 'claude', '--refresh']),
        ExitCodes.success,
      );
      expect(themeFile().readAsStringSync(),
          contains('ShadcnThemeData buildClaudeTheme'));
    });
  });

  group('registry resolution', () {
    test('no configured registry exits with registryNotFound', () async {
      expect(
        await run(<String>['list'], rootArgs: const <String>[]),
        ExitCodes.registryNotFound,
      );
    });
  });

  group('retired surface', () {
    test('theme widget is rejected as usage', () async {
      expect(await run(<String>['widget', 'list']), ExitCodes.usage);
      expect(
          capture.stderr, contains('was removed with the v1 theme manifest'));
    });

    test('--apply-file and --apply-url are rejected as usage', () async {
      expect(
          await run(<String>['--apply-file', 'theme.json']), ExitCodes.usage);
      expect(capture.stderr, contains('--apply-file/--apply-url were removed'));
    });

    test('registrySupportsTheme=false short-circuits', () async {
      final root =
          buildRootParser().parse(<String>['--registry-path', fixtureRoot]);
      final command = buildThemeParser().parse(<String>['list']);
      final exit = await capture.run(
        () => runThemeCommand(
          themeCommand: command,
          rootArgs: root,
          installer: null,
          registrySupportsTheme: false,
        ),
        projectRoot: temp.path,
      );
      expect(exit, ExitCodes.success);
      expect(capture.stdout, contains('does not provide theme presets'));
    });
  });

  group('help', () {
    test('documents both commands and the --refresh contract', () async {
      expect(await run(<String>['--help']), ExitCodes.success);
      expect(capture.stdout, contains('theme list'));
      expect(capture.stdout, contains('theme apply <preset>'));
      expect(capture.stdout, contains('--refresh'));
      expect(capture.stdout, contains('reported as drift'));
    });

    test('theme list --help short-circuits too', () async {
      expect(await run(<String>['list', '--help']), ExitCodes.success);
      expect(capture.stdout, contains('theme apply <preset>'));
    });
  });
}

/// Runs [body] with `print` and `stdout` captured and the process CWD pointed
/// at the temp project, so the command resolves `.shadcn/config.json` there.
class _Capture {
  final List<String> printed = <String>[];
  final List<String> out = <String>[];
  final List<String> err = <String>[];

  String get stdout =>
      printed.join('\n') + (out.isEmpty ? '' : '\n${out.join('\n')}');
  String get stderr => err.join('\n');

  void reset() {
    printed.clear();
    out.clear();
    err.clear();
  }

  Future<T> run<T>(Future<T> Function() body, {required String projectRoot}) {
    final previous = Directory.current;
    Directory.current = projectRoot;
    return runZoned(
      () => IOOverrides.runZoned(
        body,
        stdout: () => _RecordingSink(out),
        stderr: () => _RecordingSink(err),
      ),
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, String line) => printed.add(line),
      ),
    ).whenComplete(() => Directory.current = previous);
  }
}

/// Minimal [Stdout] stand-in: the command only ever writes lines, and the sink
/// records them so `--json` runs can be proven to keep stdout parseable.
class _RecordingSink implements Stdout {
  _RecordingSink(this.lines);

  final List<String> lines;

  @override
  Encoding encoding = utf8;

  void _record(Object? object) {
    if (object == null) return;
    final text = '$object';
    if (text.isEmpty) return;
    lines.add(text.endsWith('\n') ? text.substring(0, text.length - 1) : text);
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
