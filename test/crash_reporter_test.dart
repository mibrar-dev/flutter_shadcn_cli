import 'dart:io';

import 'package:flutter_shadcn_cli/src/crash_reporter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('CrashReporter', () {
    late Directory tempRoot;
    late Directory crashDir;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('crash_reporter_test_');
      crashDir = Directory(p.join(tempRoot.path, '.flutter_shadcn', 'crashes'));
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('redacts registry override flag values while preserving flag names',
        () {
      final redacted = CrashReporter.redactArgv([
        'add',
        '--registry-url',
        'https://secret.example/components.json',
        '--registry-path=/Users/me/private-registry',
        '--registries-path',
        '/Users/me/registries.json',
        '--json',
      ]);

      expect(redacted, [
        'add',
        '--registry-url',
        '<redacted>',
        '--registry-path=<redacted>',
        '--registries-path',
        '<redacted>',
        '--json',
      ]);
    });

    test('builds crash log with redacted command and stack trace', () {
      final reporter = CrashReporter(
        crashDirectory: crashDir,
        clock: () => DateTime.utc(2026, 5, 1, 12, 30),
        promptEnabled: false,
        writeStderr: (_) {},
      );

      final log = reporter.buildCrashLog(
        error: StateError('boom'),
        stack: StackTrace.fromString('#0 main (bin/flutter_shadcn.dart:1:1)'),
        argv: const [
          'add',
          '--registry-url',
          'https://secret.example/components.json',
        ],
      );

      expect(log, contains('flutter_shadcn Crash Report'));
      expect(log, contains('Time (UTC):     2026-05-01T12:30:00.000Z'));
      expect(
          log,
          contains(
              'Command:        flutter_shadcn add --registry-url <redacted>'));
      expect(log, contains('Exit Reason:    Unhandled exception'));
      expect(log, contains('Exception:      StateError: Bad state: boom'));
      expect(log, contains('Stack Trace:\n#0 main'));
      expect(log, isNot(contains('https://secret.example')));
    });

    test('writes crash log and prunes older logs to keep ten', () async {
      crashDir.createSync(recursive: true);
      for (var i = 0; i < 12; i++) {
        final file = File(p.join(crashDir.path, 'old_$i.log'))
          ..writeAsStringSync('old $i');
        file.setLastModifiedSync(DateTime.utc(2026, 4, 1, i));
      }

      final reporter = CrashReporter(
        crashDirectory: crashDir,
        clock: () => DateTime.utc(2026, 5, 1, 12, 30),
        promptEnabled: false,
        writeStderr: (_) {},
      );

      final written = await reporter.handleCrash(
        error: Exception('failure'),
        stack: StackTrace.current,
        argv: const ['doctor'],
      );

      expect(written.existsSync(), isTrue);
      final logs = crashDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.log'))
          .toList();
      expect(logs, hasLength(10));
      expect(logs.any((file) => p.basename(file.path) == 'old_0.log'), isFalse);
      expect(logs.any((file) => p.basename(file.path) == 'old_1.log'), isFalse);
      expect(logs.any((file) => file.path == written.path), isTrue);
    });

    test('skips prompt and browser launch when stdin is not a TTY', () async {
      final stderrBuffer = StringBuffer();
      var launched = false;
      final reporter = CrashReporter(
        crashDirectory: crashDir,
        clock: () => DateTime.utc(2026, 5, 1, 12, 30),
        promptEnabled: false,
        writeStderr: stderrBuffer.write,
        openBrowser: (_) async {
          launched = true;
        },
      );

      await reporter.handleCrash(
        error: Exception('failure'),
        stack: StackTrace.current,
        argv: const ['add', 'button'],
      );

      expect(stderrBuffer.toString(),
          contains('flutter_shadcn crashed unexpectedly'));
      expect(
          stderrBuffer.toString(), isNot(contains('Would you like to open')));
      expect(launched, isFalse);
    });

    test('opens crash issue only after explicit opt-in', () async {
      String? openedUrl;
      final reporter = CrashReporter(
        crashDirectory: crashDir,
        clock: () => DateTime.utc(2026, 5, 1, 12, 30),
        promptEnabled: true,
        readLine: () => 'y',
        writeStderr: (_) {},
        openBrowser: (url) async {
          openedUrl = url;
        },
      );

      await reporter.handleCrash(
        error: Exception('failure'),
        stack: StackTrace.fromString('#0 main'),
        argv: const ['add', '--registry-path', '/private/registry', 'button'],
      );

      expect(openedUrl, isNotNull);
      final uri = Uri.parse(openedUrl!);
      expect(uri.host, 'github.com');
      expect(uri.queryParameters['body'],
          contains('This report was generated automatically after a crash.'));
      expect(
          uri.queryParameters['body'], contains('flutter_shadcn Crash Report'));
      expect(
          uri.queryParameters['body'],
          contains(
              '1. `flutter_shadcn add --registry-path <redacted> button`'));
      expect(uri.queryParameters['body'], isNot(contains('/private/registry')));
    });
  });
}
