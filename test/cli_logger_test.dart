import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:test/test.dart';

void main() {
  group('CliLogger', () {
    test('progress writes deterministic loading feedback', () {
      final lines = <String>[];
      final logger = CliLogger(
        useColor: false,
        writeLine: lines.add,
      );

      logger.progress('Installing files for Button');

      expect(lines, ['... Installing files for Button']);
    });

    test('progress is visible when verbose is disabled', () {
      final lines = <String>[];
      final logger = CliLogger(
        verbose: false,
        useColor: false,
        writeLine: lines.add,
      );

      logger.progress('Fetching registry');
      logger.detail('cache path');

      expect(lines, ['... Fetching registry']);
    });

    test('detail is emitted only in verbose mode', () {
      final nonVerbose = <String>[];
      CliLogger(useColor: false, writeLine: nonVerbose.add).detail('hidden');

      final verbose = <String>[];
      CliLogger(
        verbose: true,
        useColor: false,
        writeLine: verbose.add,
      ).detail('shown');

      expect(nonVerbose, isEmpty);
      expect(verbose, ['  ↳ shown']);
    });

    test('non-verbose methods write in call order', () {
      final lines = <String>[];
      final logger = CliLogger(useColor: false, writeLine: lines.add);

      logger.action('Start');
      logger.progress('Working');
      logger.info('Plain');
      logger.success('Done');

      expect(lines, [
        '• Start',
        '... Working',
        'Plain',
        '✓ Done',
      ]);
    });

    test('useColor false strips ANSI styling', () {
      final lines = <String>[];
      final logger = CliLogger(useColor: false, writeLine: lines.add);

      logger.header('Header');
      logger.progress('Progress');
      logger.success('Success');
      logger.warn('Warning');
      logger.error('Error');
      logger.section('Section');

      expect(lines.join('\n'), isNot(contains('\u001b[')));
    });
  });
}
