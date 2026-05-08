part of 'installer.dart';

extension InstallerPlatformAliasPart on Installer {
  Future<void> _applyPlatformInstructions(Component component) async {
    if (component.platform.isEmpty) {
      return;
    }
    await _ensureConfigLoaded();
    await InstallerPlatformInstructionService(
      targetDir: targetDir,
      logger: logger,
    ).applyPlatformInstructions(component, _cachedConfig);
  }

  void _reportPostInstall(Component component) {
    logger.section('Post-install notes for ${component.name}');
    for (final line in component.postInstall) {
      logger.info('  • $line');
    }
  }

  Future<void> generateAliases() async {
    await _ensureConfigLoaded();
    final config = _cachedConfig ?? const ShadcnConfig();
    await InstallerAliasGeneratorService(
      targetDir: targetDir,
    ).generateAliases(
      installPath: _installPath(config),
      classPrefix: config.classPrefix,
    );
  }
}
