import 'package:flutter_shadcn_cli/src/exit_codes.dart';

class RegistryBootstrapException implements Exception {
  final String registryRoot;
  final String message;
  final int? explicitExitCode;

  const RegistryBootstrapException(
    this.registryRoot,
    this.message, [
    this.explicitExitCode,
  ]);

  int exitCode() {
    if (explicitExitCode != null) {
      return explicitExitCode!;
    }
    if (message.contains('Offline mode')) {
      return ExitCodes.offlineUnavailable;
    }
    if (message.contains('Failed to fetch')) {
      return ExitCodes.networkError;
    }
    if (message.contains('schema validation failed')) {
      return ExitCodes.schemaInvalid;
    }
    return ExitCodes.registryNotFound;
  }
}
