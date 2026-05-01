import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/version_manager.dart';

Future<int> runUpgradeCommand({
  required ArgResults command,
  required CliLogger logger,
}) async {
  if (command['help'] == true) {
    print('Usage: flutter_shadcn upgrade [--force]');
    print('');
    print('Upgrades flutter_shadcn_cli to the latest version from pub.dev.');
    print('');
    print('Options:');
    print(
        '  --force, -f        Force upgrade even if already on latest version');
    print('  --help, -h         Show this message');
    return ExitCodes.success;
  }
  final versionMgr = VersionManager(logger: logger);
  await versionMgr.upgrade(force: command['force'] == true);
  return ExitCodes.success;
}
