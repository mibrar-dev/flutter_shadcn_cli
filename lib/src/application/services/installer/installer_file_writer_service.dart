import 'dart:io';

import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';

class InstallerFileWriterService {
  InstallerFileWriterService({
    required this.registry,
    required this.logger,
  });

  final Registry registry;
  final CliLogger logger;

  Future<void> writeRegistryFile({
    required RegistryFile file,
    required String destinationPath,
    required bool shouldInstall,
  }) async {
    final destFile = File(destinationPath);
    if (!await destFile.parent.exists()) {
      await destFile.parent.create(recursive: true);
    }

    if (!shouldInstall) {
      logger.detail('Skipping optional ${file.destination}');
      return;
    }

    logger.detail('Writing ${destFile.path}');
    final bytes = await registry.readSourceBytes(file.source);
    await destFile.writeAsBytes(bytes, flush: true);
  }
}
