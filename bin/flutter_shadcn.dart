import 'dart:async';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/crash_reporter.dart';

import 'shadcn.dart' as cli;

Future<void> main(List<String> arguments) async {
  final argv = List<String>.of(arguments);
  await runZonedGuarded(
    () async {
      await CrashReporter.pruneOldLogsOnStartup();
      await cli.run(argv);
    },
    (error, stack) async {
      await CrashReporter.handle(
        error: error,
        stack: stack,
        argv: argv,
      );
      exit(1);
    },
  );
}
