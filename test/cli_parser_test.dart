import 'dart:async';

import 'package:flutter_shadcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/usage.dart';
import 'package:test/test.dart';

void main() {
  group('CLI parser', () {
    test('rejects removed public registry selector', () {
      final parser = buildCliParser();

      expect(
        () => parser.parse(['--registry', 'local', 'list']),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects removed registries url override', () {
      final parser = buildCliParser();

      expect(
        () => parser.parse([
          '--registries-url',
          'https://example.com/registries.json',
          'list',
        ]),
        throwsA(isA<FormatException>()),
      );
    });

    test('keeps developer registry flags parseable', () {
      final parser = buildCliParser();
      final results = parser.parse([
        '--registry-path',
        '/tmp/registry',
        '--registry-url',
        'https://example.com/registry',
        '--registries-path',
        '/tmp/registries.json',
        '--skip-integrity',
        'list',
      ]);

      expect(results['registry-path'], '/tmp/registry');
      expect(results['registry-url'], 'https://example.com/registry');
      expect(results['registries-path'], '/tmp/registries.json');
      expect(results['skip-integrity'], isTrue);
      expect(results.command?.name, 'list');
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

    test('hides developer registry flags from parser usage', () {
      final parser = buildCliParser();
      final usage = parser.usage;

      expect(usage, contains('--registry-name'));
      expect(_usageFlagNames(usage), isNot(contains('--registry')));
      expect(_usageFlagNames(usage), isNot(contains('--registry-path')));
      expect(_usageFlagNames(usage), isNot(contains('--registry-url')));
      expect(_usageFlagNames(usage), isNot(contains('--registries-path')));
      expect(_usageFlagNames(usage), isNot(contains('--skip-integrity')));
    });

    test('removes public registry override wording from root usage', () {
      final output = _capturePrint(printCliUsage);

      expect(output, contains('--registry-name'));
      expect(output, isNot(contains('--registry ')));
      expect(output, isNot(contains('--registry-path')));
      expect(output, isNot(contains('--registry-url')));
      expect(output, isNot(contains('--registries-path')));
      expect(output, isNot(contains('--registries-url')));
      expect(output, isNot(contains('--skip-integrity')));
    });

    test('advanced root usage shows advanced-only commands and flags', () {
      final output = _capturePrint(() => printCliUsage(advanced: true));

      expect(output, contains('docs'));
      expect(output, contains('install-skill'));
      expect(output, contains('--advanced'));
      expect(output, contains('--registry-path'));
      expect(output, contains('--registry-url'));
      expect(output, contains('--registries-path'));
      expect(output, contains('--skip-integrity'));
    });

    test('theme import flags are hidden from normal parser usage', () {
      final usage = buildCliParser().commands['theme']!.usage;

      expect(usage, isNot(contains('--apply-file')));
      expect(usage, isNot(contains('--apply-url')));
    });

    test('theme import flags remain parseable', () {
      final parser = buildCliParser();
      final results = parser.parse(
        normalizeCliArgs([
          '--advanced',
          'theme',
          '--apply-file',
          'theme.json',
        ]),
      );

      expect(results.command?['apply-file'], 'theme.json');
    });

    test('hoists hidden developer flags after subcommands', () {
      final normalized = normalizeCliArgs([
        '--offline',
        'add',
        'button',
        '--registry-path',
        '/tmp/registry',
        '--skip-integrity',
      ]);

      expect(
        normalized,
        [
          '--offline',
          '--registry-path',
          '/tmp/registry',
          '--skip-integrity',
          'add',
          'button',
        ],
      );
    });

    test('normalizes theme namespace token before widget subcommand', () {
      final normalized = normalizeCliArgs([
        'theme',
        '@shadcn',
        'widget',
        'button',
        '--list-targets',
      ]);

      expect(
        normalized,
        ['theme', 'widget', '@shadcn', 'button', '--list-targets'],
      );
    });

    test('parses nested theme widget command', () {
      final parser = buildCliParser();
      final results = parser.parse([
        'theme',
        'widget',
        '@shadcn',
        'button',
        '--list-targets',
      ]);

      expect(results.command?.name, 'theme');
      expect(results.command?.command?.name, 'widget');
      expect(results.command?.command?.rest, ['@shadcn', 'button']);
      expect(results.command?.command?['list-targets'], isTrue);
    });
  });
}

Set<String> _usageFlagNames(String usage) {
  return RegExp(r'--[a-z][a-z-]*')
      .allMatches(usage)
      .map((match) => match.group(0)!)
      .toSet();
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
