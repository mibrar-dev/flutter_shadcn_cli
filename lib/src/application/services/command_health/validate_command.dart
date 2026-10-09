import 'package:flutter_shadcn_cli/src/application/services/registry_manifest_loader.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_source.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';

/// `validate`: load `manifests/registry.json` and check it against the v2 rules
/// (P5_CLI_PLAN.md §2, §6.1). Exit `20` (`schemaInvalid`) on any violation.
Future<int> runValidateCommand({
  required RegistrySource source,
  required bool jsonOutput,
  required CliLogger logger,
}) async {
  try {
    final loaded = await RegistryManifestLoader(source).load();
    if (jsonOutput) {
      printJson(jsonEnvelope(
        command: 'validate',
        data: {
          'manifest': loaded.path,
          'sha256': loaded.sha256,
          'components': loaded.manifest.components.length,
          'primitives': loaded.manifest.primitives.length,
          'themes': loaded.manifest.themes.length,
          'valid': true,
        },
        meta: {'exitCode': ExitCodes.success},
      ));
    } else {
      logger.header('Registry validation');
      logger.success(
        '${source.describe(loaded.path)} is a valid v2 manifest '
        '(${loaded.manifest.components.length} components, '
        '${loaded.manifest.themes.length} themes).',
      );
    }
    return ExitCodes.success;
  } on RegistryManifestException catch (error) {
    final code =
        error.notFound ? ExitCodes.registryNotFound : ExitCodes.schemaInvalid;
    if (jsonOutput) {
      printJson(jsonEnvelope(
        command: 'validate',
        data: {'valid': false},
        errors: [
          jsonError(
            code: error.notFound
                ? ExitCodeLabels.registryNotFound
                : ExitCodeLabels.schemaInvalid,
            message: error.message,
            details: {'issues': error.details},
          ),
        ],
        meta: {'exitCode': code},
      ));
    } else {
      logger.error(error.message);
      for (final issue in error.details) {
        logger.info('  - $issue');
      }
    }
    return code;
  } on RegistrySourceException catch (error) {
    final offline = error.message.contains('Offline mode');
    final notFound = error.message.contains('Local registry not found');
    final code = offline
        ? ExitCodes.offlineUnavailable
        : notFound
            ? ExitCodes.registryNotFound
            : ExitCodes.networkError;
    if (jsonOutput) {
      printJson(jsonEnvelope(
        command: 'validate',
        data: const {},
        errors: [
          jsonError(
            code: offline
                ? ExitCodeLabels.offlineUnavailable
                : notFound
                    ? ExitCodeLabels.registryNotFound
                    : ExitCodeLabels.networkError,
            message: error.message,
            details: {'details': error.details},
          ),
        ],
        meta: {'exitCode': code},
      ));
    } else {
      logger.error(error.message);
    }
    return code;
  }
}
