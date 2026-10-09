import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/application/services/manifest_closure.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_manifest_loader.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_source.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_models.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/arg_helpers.dart';

/// A command reads its flags through these helpers so the parser stays the
/// single source of truth and unknown flags degrade to `false`/`null`.
bool commandFlag(ArgResults args, String name) =>
    optionalBoolOption(args, name);

String? commandOption(ArgResults args, String name) =>
    optionalStringOption(args, name);

/// Builds a logger that keeps STDOUT parseable when `--json` is active: all
/// human lines go to STDERR, warnings/errors to STDERR as well.
CliLogger commandLogger(ArgResults rootArgs, {required bool json}) {
  return CliLogger(
    verbose: commandFlag(rootArgs, 'verbose'),
    useColor: !json,
    writeLine: json ? stderr.writeln : stdout.writeln,
    writeStderrLine: stderr.writeln,
  );
}

/// The global `--registry <path|url>` override, when present.
String? registryOverrideFrom(ArgResults rootArgs) =>
    commandOption(rootArgs, 'registry');

/// Strips a `@namespace/` prefix from a component address; bare ids and
/// malformed refs pass through unchanged.
String bareComponentId(String token) {
  final trimmed = token.trim();
  if (trimmed.startsWith('@') && trimmed.contains('/')) {
    return trimmed.substring(trimmed.indexOf('/') + 1).trim();
  }
  return trimmed;
}

/// Component ids from a command's positional arguments.
List<String> componentIdsFrom(ArgResults command) {
  return [
    for (final token in command.rest)
      if (bareComponentId(token).isNotEmpty) bareComponentId(token),
  ];
}

/// Maps a thrown error to a CLI exit code, printing it first.
int reportCommandError(Object error, CliLogger logger) {
  switch (error) {
    case RegistryManifestException():
      for (final line in [error.message, ...error.details]) {
        logger.errorToStderr('Error: $line');
      }
      if (error.notFound) {
        return ExitCodes.registryNotFound;
      }
      return error.isSchemaInvalid
          ? ExitCodes.schemaInvalid
          : ExitCodes.validationFailed;
    case RegistrySourceException():
      for (final line in [error.message, ...error.details]) {
        logger.errorToStderr('Error: $line');
      }
      if (error.message.contains('Offline mode')) {
        return ExitCodes.offlineUnavailable;
      }
      if (error.message.contains('Local registry not found')) {
        return ExitCodes.registryNotFound;
      }
      return ExitCodes.networkError;
    case ManifestClosureException():
      logger.errorToStderr('Error: $error');
      return ExitCodes.componentMissing;
    case SingleOwnerViolationException():
      logger.errorToStderr('Error: $error');
      return ExitCodes.validationFailed;
    case LockFileException():
      logger.errorToStderr('Error: $error');
      return ExitCodes.validationFailed;
    case ThemeApplyException():
      for (final line in error.lines) {
        logger.errorToStderr('Error: $line');
      }
      return ExitCodes.validationFailed;
    default:
      logger.errorToStderr('Error: $error');
      return ExitCodes.ioError;
  }
}
