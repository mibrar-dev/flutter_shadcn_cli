part of 'installer.dart';

extension InstallerDryRunPart on Installer {
  Future<DryRunPlan> buildDryRunPlan(
    List<String> componentIds, {
    bool includeDependencies = true,
  }) async {
    await _ensureConfigLoaded();
    return InstallerDryRunService(
      registry: registry,
      targetDir: targetDir,
      config: _cachedConfig,
      configResolver: _configResolver,
      logger: logger,
    ).buildPlan(componentIds, includeDependencies: includeDependencies);
  }

  void printDryRunPlan(DryRunPlan plan) {
    InstallerDryRunService(
      registry: registry,
      targetDir: targetDir,
      config: _cachedConfig,
      configResolver: _configResolver,
      logger: logger,
    ).printPlan(plan);
  }
}
