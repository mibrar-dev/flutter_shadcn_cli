import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/installer.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/multi_registry_manager.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/arg_helpers.dart';

Future<int> runAssetsCommand({
  required ArgResults command,
  required Installer? installer,
  required MultiRegistryManager multiRegistry,
  required ArgResults rootArgs,
  required ShadcnConfig config,
  required CliLogger logger,
}) async {
  if (command['help'] == true) {
    print('Usage: flutter_shadcn assets [options]');
    print('');
    print('Options:');
    print('  --icons            Install icon font assets');
    print('  --typography       Install typography font assets');
    print('  --fonts            Alias for --typography');
    print('  --list             List available assets');
    print('  --all, -a          Install both icon + typography fonts');
    print('  --help, -h         Show this message');
    return ExitCodes.success;
  }
  if (command['list'] == true) {
    print('Available assets are defined by inline registry actions.');
    return ExitCodes.success;
  }

  final installAll = command['all'] == true;
  final installIcons = command['icons'] == true;
  final installTypography =
      command['typography'] == true || command['fonts'] == true;
  if (!installAll && !installIcons && !installTypography) {
    print('Nothing selected. Use --icons, --typography, or --all.');
    return ExitCodes.usage;
  }

  final inlineHandled = await multiRegistry.runInlineAssets(
    namespace: selectedNamespaceForCommand(rootArgs, config),
    installIcons: installIcons,
    installTypography: installTypography,
    installAll: installAll,
  );
  if (inlineHandled) {
    logger.success('Installed assets via inline registry actions.');
    return ExitCodes.success;
  }

  stderr.writeln(
    'Error: No inline registry actions are available for the selected assets.',
  );
  return ExitCodes.componentMissing;
}
