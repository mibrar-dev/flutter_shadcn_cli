import 'package:flutter_shadcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:test/test.dart';

void main() {
  group('CLI parser', () {
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
