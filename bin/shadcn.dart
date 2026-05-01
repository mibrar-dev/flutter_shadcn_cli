import 'dart:async';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/crash_reporter.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/bootstrap.dart';

Future<void> main(List<String> arguments) async {
  final argv = List<String>.of(arguments);
  await runZonedGuarded(
    () async {
      await CrashReporter.pruneOldLogsOnStartup();
      await run(argv);
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

Future<void> run(List<String> arguments) async {
  await runCliBootstrap(arguments);
}
