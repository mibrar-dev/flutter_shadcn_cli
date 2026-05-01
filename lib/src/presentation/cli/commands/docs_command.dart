import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/docs_generator.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';

Future<int> runDocsCommand({
  required ArgResults command,
  required String? cliRoot,
  required CliLogger logger,
}) async {
  if (command['help'] == true) {
    print('Usage: flutter_shadcn docs [--generate]');
    print('');
    print('Regenerate docs/reference/commands from CLI metadata.');
    print('Options:');
    print('  --generate, -g     Regenerate command reference docs (default)');
    print('  --help, -h         Show this message');
    return ExitCodes.success;
  }
  if (cliRoot == null) {
    return ExitCodes.ioError;
  }
  await generateDocsSite(cliRoot: cliRoot, logger: logger);
  return ExitCodes.success;
}
