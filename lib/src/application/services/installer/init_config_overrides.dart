class InitConfigOverrides {
  final String? installPath;
  final String? sharedPath;
  final bool? includeReadme;
  final bool? includeMeta;
  final bool? includePreview;
  final String? classPrefix;
  final Map<String, String>? pathAliases;

  const InitConfigOverrides({
    this.installPath,
    this.sharedPath,
    this.includeReadme,
    this.includeMeta,
    this.includePreview,
    this.classPrefix,
    this.pathAliases,
  });

  bool get hasAny {
    return installPath != null ||
        sharedPath != null ||
        includeReadme != null ||
        includeMeta != null ||
        includePreview != null ||
        classPrefix != null ||
        pathAliases != null;
  }
}
