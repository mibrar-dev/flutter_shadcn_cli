import 'dart:async';

import 'package:flutter_shadcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/usage.dart';
import 'package:test/test.dart';

void main() {
  group('CLI parser', () {
    test('parses the --registry source override', () {
      final parser = buildCliParser();
      final results = parser.parse([
        '--registry',
        '/tmp/registry',
        'list',
      ]);

      expect(results['registry'], '/tmp/registry');
      expect(results.command?.name, 'list');
    });

    test('rejects retired registry selectors', () {
      final parser = buildCliParser();
      for (final flag in const [
        '--registry-path',
        '--registry-url',
        '--registries-path',
        '--registries-url',
        '--skip-integrity',
      ]) {
        expect(
          () => parser.parse([flag, 'value', 'list']),
          throwsA(isA<FormatException>()),
          reason: '$flag should be retired',
        );
      }
    });

    test('retired commands are gone', () {
      final parser = buildCliParser();
      for (final name in const ['assets', 'locale', 'platform', 'deps']) {
        expect(parser.commands.containsKey(name), isFalse, reason: name);
      }
      expect(parser.commands.containsKey('update'), isTrue);
    });

    test('advanced flag is accepted before command', () {
      final parser = buildCliParser();
      final results = parser.parse(normalizeCliArgs(['--advanced', 'list']));

      expect(results['advanced'], isTrue);
      expect(results.command?.name, 'list');
    });

    test('advanced flag is accepted after command', () {
      final parser = buildCliParser();
      final results = parser.parse(
        normalizeCliArgs(['docs', '--advanced', '--generate']),
      );

      expect(results['advanced'], isTrue);
      expect(results.command?.name, 'docs');
      expect(results.command?['generate'], isTrue);
    });

    test('json flag is accepted before json-enabled command', () {
      final parser = buildCliParser();
      final results = parser.parse(
        normalizeCliArgs(['--json', 'list', 'button']),
      );

      expect(results.command?.name, 'list');
      expect(results.command?['json'], isTrue);
      expect(results.command?.rest, ['button']);
    });

    test('json flag is accepted after json-enabled command arguments', () {
      final parser = buildCliParser();
      final results = parser.parse(
        normalizeCliArgs(['search', 'button', '--json']),
      );

      expect(results.command?.name, 'search');
      expect(results.command?['json'], isTrue);
      expect(results.command?.rest, ['button']);
    });

    test('json flag remains invalid for commands without json output', () {
      final parser = buildCliParser();

      expect(
        () => parser.parse(normalizeCliArgs(['--json', 'version'])),
        throwsA(isA<FormatException>()),
      );
    });

    test('root usage shows --registry and not the retired flags', () {
      final output = _capturePrint(printCliUsage);

      expect(output, contains('--registry-name'));
      expect(output, contains('--registry'));
      expect(output, isNot(contains('--registry-path')));
      expect(output, isNot(contains('--registry-url')));
      expect(output, isNot(contains('--registries-path')));
      expect(output, isNot(contains('--skip-integrity')));
    });

    test('advanced root usage shows advanced-only commands', () {
      final output = _capturePrint(() => printCliUsage(advanced: true));

      expect(output, contains('docs'));
      expect(output, contains('--advanced'));
      expect(output, isNot(contains('--registry-path')));
    });

    test('add exposes the v2 flags', () {
      final parser = buildCliParser();
      final results = parser.parse([
        'add',
        'button',
        '--dry-run',
        '--force',
        '--include-preview',
        '--json',
      ]);

      expect(results.command?['dry-run'], isTrue);
      expect(results.command?['force'], isTrue);
      expect(results.command?['include-preview'], isTrue);
      expect(results.command?['json'], isTrue);
    });

    test('update exposes --all, --check and --json', () {
      final parser = buildCliParser();
      final results = parser.parse(['update', '--all', '--check', '--json']);

      expect(results.command?['all'], isTrue);
      expect(results.command?['check'], isTrue);
      expect(results.command?['json'], isTrue);
    });

    test('init exposes --dir and --theme', () {
      final parser = buildCliParser();
      final results =
          parser.parse(['init', '--dir', 'lib/x', '--theme', 'vercel']);

      expect(results.command?['dir'], 'lib/x');
      expect(results.command?['theme'], 'vercel');
    });

    test('theme import flags are gone from the parser', () {
      final parser = buildCliParser();
      final theme = parser.commands['theme']!;

      expect(theme.options.containsKey('apply-file'), isFalse);
      expect(theme.options.containsKey('apply-url'), isFalse);
      expect(theme.commands.containsKey('widget'), isFalse);
    });

    test('parses nested theme apply subcommand', () {
      final parser = buildCliParser();
      final results = parser.parse(['theme', 'apply', 'vercel', '--refresh']);

      expect(results.command?.name, 'theme');
      expect(results.command?.command?.name, 'apply');
      expect(results.command?.command?.rest, ['vercel']);
      expect(results.command?.command?['refresh'], isTrue);
    });

    test('parses top-level reset command', () {
      final parser = buildCliParser();
      final results = parser.parse(['reset']);

      expect(results.command?.name, 'reset');
    });

    test('parses project reset subcommand and undo flag', () {
      final parser = buildCliParser();
      final results = parser.parse(['project', 'reset', '--undo']);

      expect(results.command?.name, 'project');
      expect(results.command?.command?.name, 'reset');
      expect(results.command?.command?['undo'], isTrue);
    });

    test('shows reset and project commands in normal usage', () {
      final output = _capturePrint(printCliUsage);

      expect(output, contains('reset'));
      expect(output, contains('project'));
    });
  });
}

String _capturePrint(void Function() callback) {
  final lines = <String>[];
  runZoned(
    callback,
    zoneSpecification: ZoneSpecification(
      print: (_, __, ___, line) => lines.add(line),
    ),
  );
  return lines.join('\n');
}
