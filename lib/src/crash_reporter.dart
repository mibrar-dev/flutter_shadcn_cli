import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/feedback/feedback_manager.dart';
import 'package:flutter_shadcn_cli/src/application/services/version/version_manager.dart';

typedef BrowserLauncher = Future<void> Function(String url);

class CrashReporter {
  static const _maxCrashLogs = 10;
  static const _redactedValue = '<redacted>';
  static const _sensitiveFlags = {
    '--registry-url',
    '--registry-path',
    '--registries-path',
  };

  final Directory crashDirectory;
  final DateTime Function() clock;
  final bool promptEnabled;
  final String? Function() readLine;
  final void Function(String value) writeStderr;
  final BrowserLauncher openBrowser;

  CrashReporter({
    required this.crashDirectory,
    DateTime Function()? clock,
    bool? promptEnabled,
    String? Function()? readLine,
    void Function(String value)? writeStderr,
    BrowserLauncher? openBrowser,
  })  : clock = clock ?? (() => DateTime.now().toUtc()),
        promptEnabled = promptEnabled ?? stdin.hasTerminal,
        readLine = readLine ?? stdin.readLineSync,
        writeStderr = writeStderr ?? stderr.write,
        openBrowser = openBrowser ?? _openInBrowser;

  factory CrashReporter.defaults() {
    return CrashReporter(
      crashDirectory: Directory(
        _joinPath(_homeDir(), '.flutter_shadcn', 'crashes'),
      ),
    );
  }

  static Future<void> pruneOldLogsOnStartup() async {
    await CrashReporter.defaults().pruneOldLogs();
  }

  static Future<void> handle({
    required Object error,
    required StackTrace stack,
    required List<String> argv,
  }) async {
    await CrashReporter.defaults().handleCrash(
      error: error,
      stack: stack,
      argv: argv,
    );
  }

  Future<File> handleCrash({
    required Object error,
    required StackTrace stack,
    required List<String> argv,
  }) async {
    final crashLog = buildCrashLog(error: error, stack: stack, argv: argv);
    final file = await writeCrashLog(crashLog);
    await pruneOldLogs();

    writeStderr('✖ flutter_shadcn crashed unexpectedly.\n\n');
    writeStderr('Crash log saved to: ${_displayPath(file)}\n\n');

    if (promptEnabled) {
      writeStderr(
        'Would you like to open a GitHub issue with this report pre-filled? (y/N): ',
      );
      final input = readLine()?.trim().toLowerCase();
      if (input == 'y') {
        await openBrowser(
          buildCrashIssueUrl(
            crashLog: crashLog,
            argv: argv,
            error: error,
          ),
        );
      }
    }

    return file;
  }

  String buildCrashLog({
    required Object error,
    required StackTrace stack,
    required List<String> argv,
  }) {
    final timestamp = clock().toUtc().toIso8601String();
    final command = reconstructCommand(argv);
    final exceptionType = error.runtimeType.toString();
    final exceptionMessage = _exceptionMessage(error);
    return '''
flutter_shadcn Crash Report
============================
Time (UTC):     $timestamp
CLI Version:    ${VersionManager.currentVersion}
Dart:           ${Platform.version}
OS:             ${Platform.operatingSystem} ${Platform.operatingSystemVersion}

Command:        $command
Exit Reason:    Unhandled exception

Exception:      $exceptionType: $exceptionMessage

Stack Trace:
$stack
''';
  }

  Future<File> writeCrashLog(String crashLog) async {
    if (!crashDirectory.existsSync()) {
      crashDirectory.createSync(recursive: true);
    }
    final timestamp = clock()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file = File(_joinPath(crashDirectory.path, '$timestamp.log'));
    await file.writeAsString(crashLog, flush: true);
    return file;
  }

  Future<void> pruneOldLogs() async {
    if (!crashDirectory.existsSync()) {
      return;
    }
    final logs = crashDirectory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.log'))
        .toList()
      ..sort((left, right) {
        final byModified = right.lastModifiedSync().compareTo(
              left.lastModifiedSync(),
            );
        if (byModified != 0) {
          return byModified;
        }
        return _basename(right.path).compareTo(_basename(left.path));
      });

    for (final file in logs.skip(_maxCrashLogs)) {
      try {
        file.deleteSync();
      } catch (_) {
        // Best-effort cleanup must not hide the original crash.
      }
    }
  }

  String buildCrashIssueUrl({
    required String crashLog,
    required List<String> argv,
    required Object error,
  }) {
    final issueTitle = Uri.encodeComponent(
      'Crash report: ${error.runtimeType}',
    );
    final body = Uri.encodeComponent(buildCrashIssueBody(
      crashLog: crashLog,
      argv: argv,
    ));
    final labels = Uri.encodeComponent('bug,crash,cli');
    return 'https://github.com/${FeedbackManager.repoOwner}/${FeedbackManager.repoName}/issues/new?title=$issueTitle&body=$body&labels=$labels';
  }

  String buildCrashIssueBody({
    required String crashLog,
    required List<String> argv,
  }) {
    return '''
> This report was generated automatically after a crash. Please review and remove any sensitive information before submitting.

## Crash Report

```text
$crashLog
```

## Steps to Reproduce

<!-- Add any steps that happened before this command. -->

1. `${reconstructCommand(argv)}`
2.
''';
  }

  static List<String> redactArgv(List<String> argv) {
    final redacted = <String>[];
    var redactNext = false;

    for (final arg in argv) {
      if (redactNext) {
        redacted.add(_redactedValue);
        redactNext = false;
        continue;
      }

      final equalsIndex = arg.indexOf('=');
      if (equalsIndex > 0) {
        final flag = arg.substring(0, equalsIndex);
        if (_sensitiveFlags.contains(flag)) {
          redacted.add('$flag=$_redactedValue');
          continue;
        }
      }

      if (_sensitiveFlags.contains(arg)) {
        redacted.add(arg);
        redactNext = true;
        continue;
      }

      redacted.add(arg);
    }

    return redacted;
  }

  static String reconstructCommand(List<String> argv) {
    final args = redactArgv(argv).map(_quoteArg).join(' ');
    return args.isEmpty ? 'flutter_shadcn' : 'flutter_shadcn $args';
  }

  static String _exceptionMessage(Object error) {
    final type = error.runtimeType.toString();
    final value = error.toString();
    final prefix = '$type: ';
    if (value.startsWith(prefix)) {
      return value.substring(prefix.length);
    }
    return value;
  }

  static String _quoteArg(String arg) {
    if (arg.isEmpty) {
      return "''";
    }
    if (!RegExp(r'''[\s'"\\$]''').hasMatch(arg)) {
      return arg;
    }
    return "'${arg.replaceAll("'", r"'\''")}'";
  }

  static String _displayPath(File file) {
    final home = _homeDir();
    if (home.isNotEmpty) {
      final normalizedHome = _normalizePath(home);
      final normalizedFile = _normalizePath(file.path);
      if (normalizedFile == normalizedHome) {
        return '~';
      }
      final prefix = '$normalizedHome/';
      if (normalizedFile.startsWith(prefix)) {
        return '~/${normalizedFile.substring(prefix.length)}';
      }
    }
    return file.path;
  }

  static String _homeDir() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      return env['USERPROFILE'] ?? env['HOME'] ?? '.';
    }
    return env['HOME'] ?? '.';
  }

  static String _joinPath(
    String left,
    String middle, [
    String? right,
  ]) {
    final separator = Platform.pathSeparator;
    final parts = [left, middle, if (right != null) right]
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part.replaceAll(RegExp(r'[\\/]+$'), ''))
        .toList();
    return parts.join(separator);
  }

  static String _normalizePath(String value) {
    return value.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  }

  static String _basename(String value) {
    final normalized = _normalizePath(value);
    final index = normalized.lastIndexOf('/');
    if (index < 0) {
      return normalized;
    }
    return normalized.substring(index + 1);
  }

  static Future<void> _openInBrowser(String url) async {
    String command;
    List<String> args;

    if (Platform.isMacOS) {
      command = 'open';
      args = [url];
    } else if (Platform.isLinux) {
      command = 'xdg-open';
      args = [url];
    } else if (Platform.isWindows) {
      command = 'cmd';
      args = ['/c', 'start', url];
    } else {
      return;
    }

    await Process.run(command, args);
  }
}
