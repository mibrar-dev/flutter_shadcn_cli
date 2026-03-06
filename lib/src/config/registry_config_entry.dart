class RegistryConfigEntry {
  final String? registryMode;
  final String? registryPath;
  final String? registryUrl;
  final String? baseUrl;
  final String? componentsPath;
  final String? componentsSchemaPath;
  final String? indexPath;
  final String? indexSchemaPath;
  final String? themesPath;
  final String? themesSchemaPath;
  final String? folderStructurePath;
  final String? metaPath;
  final String? themeConverterDartPath;
  final String? installPath;
  final String? sharedPath;
  final bool? includeReadme;
  final bool? includeMeta;
  final bool? includePreview;
  final List<String>? includeFiles;
  final List<String>? excludeFiles;
  final bool? capabilitySharedGroups;
  final bool? capabilityComposites;
  final bool? capabilityTheme;
  final String? trustMode;
  final String? trustSha256;
  final bool enabled;

  const RegistryConfigEntry({
    this.registryMode,
    this.registryPath,
    this.registryUrl,
    this.baseUrl,
    this.componentsPath,
    this.componentsSchemaPath,
    this.indexPath,
    this.indexSchemaPath,
    this.themesPath,
    this.themesSchemaPath,
    this.folderStructurePath,
    this.metaPath,
    this.themeConverterDartPath,
    this.installPath,
    this.sharedPath,
    this.includeReadme,
    this.includeMeta,
    this.includePreview,
    this.includeFiles,
    this.excludeFiles,
    this.capabilitySharedGroups,
    this.capabilityComposites,
    this.capabilityTheme,
    this.trustMode,
    this.trustSha256,
    this.enabled = true,
  });

  factory RegistryConfigEntry.fromJson(Map<String, dynamic> json) {
    return RegistryConfigEntry(
      registryMode: json['registryMode'] as String?,
      registryPath: json['registryPath'] as String?,
      registryUrl: json['registryUrl'] as String?,
      baseUrl: json['baseUrl'] as String?,
      componentsPath: json['componentsPath'] as String?,
      componentsSchemaPath: json['componentsSchemaPath'] as String?,
      indexPath: json['indexPath'] as String?,
      indexSchemaPath: json['indexSchemaPath'] as String?,
      themesPath: json['themesPath'] as String?,
      themesSchemaPath: json['themesSchemaPath'] as String?,
      folderStructurePath: json['folderStructurePath'] as String?,
      metaPath: json['metaPath'] as String?,
      themeConverterDartPath: json['themeConverterDartPath'] as String?,
      installPath: json['installPath'] as String?,
      sharedPath: json['sharedPath'] as String?,
      includeReadme: json['includeReadme'] as bool?,
      includeMeta: json['includeMeta'] as bool?,
      includePreview: json['includePreview'] as bool?,
      includeFiles: _stringListOrNull(json['includeFiles']),
      excludeFiles: _stringListOrNull(json['excludeFiles']),
      capabilitySharedGroups: json['capabilitySharedGroups'] as bool?,
      capabilityComposites: json['capabilityComposites'] as bool?,
      capabilityTheme: json['capabilityTheme'] as bool?,
      trustMode: json['trustMode'] as String?,
      trustSha256: json['trustSha256'] as String?,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'enabled': enabled};
    void add(String key, Object? value) {
      if (value != null) {
        json[key] = value;
      }
    }

    add('registryMode', registryMode);
    add('registryPath', registryPath);
    add('registryUrl', registryUrl);
    add('baseUrl', baseUrl);
    add('componentsPath', componentsPath);
    add('componentsSchemaPath', componentsSchemaPath);
    add('indexPath', indexPath);
    add('indexSchemaPath', indexSchemaPath);
    add('themesPath', themesPath);
    add('themesSchemaPath', themesSchemaPath);
    add('folderStructurePath', folderStructurePath);
    add('metaPath', metaPath);
    add('themeConverterDartPath', themeConverterDartPath);
    add('installPath', installPath);
    add('sharedPath', sharedPath);
    add('includeReadme', includeReadme);
    add('includeMeta', includeMeta);
    add('includePreview', includePreview);
    add('includeFiles', includeFiles);
    add('excludeFiles', excludeFiles);
    add('capabilitySharedGroups', capabilitySharedGroups);
    add('capabilityComposites', capabilityComposites);
    add('capabilityTheme', capabilityTheme);
    add('trustMode', trustMode);
    add('trustSha256', trustSha256);
    return json;
  }

  RegistryConfigEntry copyWith({
    String? registryMode,
    String? registryPath,
    String? registryUrl,
    String? baseUrl,
    String? componentsPath,
    String? componentsSchemaPath,
    String? indexPath,
    String? indexSchemaPath,
    String? themesPath,
    String? themesSchemaPath,
    String? folderStructurePath,
    String? metaPath,
    String? themeConverterDartPath,
    String? installPath,
    String? sharedPath,
    bool? includeReadme,
    bool? includeMeta,
    bool? includePreview,
    List<String>? includeFiles,
    List<String>? excludeFiles,
    bool? capabilitySharedGroups,
    bool? capabilityComposites,
    bool? capabilityTheme,
    String? trustMode,
    String? trustSha256,
    bool? enabled,
  }) {
    return RegistryConfigEntry(
      registryMode: registryMode ?? this.registryMode,
      registryPath: registryPath ?? this.registryPath,
      registryUrl: registryUrl ?? this.registryUrl,
      baseUrl: baseUrl ?? this.baseUrl,
      componentsPath: componentsPath ?? this.componentsPath,
      componentsSchemaPath: componentsSchemaPath ?? this.componentsSchemaPath,
      indexPath: indexPath ?? this.indexPath,
      indexSchemaPath: indexSchemaPath ?? this.indexSchemaPath,
      themesPath: themesPath ?? this.themesPath,
      themesSchemaPath: themesSchemaPath ?? this.themesSchemaPath,
      folderStructurePath: folderStructurePath ?? this.folderStructurePath,
      metaPath: metaPath ?? this.metaPath,
      themeConverterDartPath:
          themeConverterDartPath ?? this.themeConverterDartPath,
      installPath: installPath ?? this.installPath,
      sharedPath: sharedPath ?? this.sharedPath,
      includeReadme: includeReadme ?? this.includeReadme,
      includeMeta: includeMeta ?? this.includeMeta,
      includePreview: includePreview ?? this.includePreview,
      includeFiles: includeFiles ?? this.includeFiles,
      excludeFiles: excludeFiles ?? this.excludeFiles,
      capabilitySharedGroups:
          capabilitySharedGroups ?? this.capabilitySharedGroups,
      capabilityComposites: capabilityComposites ?? this.capabilityComposites,
      capabilityTheme: capabilityTheme ?? this.capabilityTheme,
      trustMode: trustMode ?? this.trustMode,
      trustSha256: trustSha256 ?? this.trustSha256,
      enabled: enabled ?? this.enabled,
    );
  }
}

List<String>? _stringListOrNull(dynamic raw) {
  if (raw is! List) {
    return null;
  }
  final values = raw
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
  return values.isEmpty ? null : values;
}
