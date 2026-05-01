const Object _copyWithUnset = Object();

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
    Object? registryMode = _copyWithUnset,
    Object? registryPath = _copyWithUnset,
    Object? registryUrl = _copyWithUnset,
    Object? baseUrl = _copyWithUnset,
    Object? componentsPath = _copyWithUnset,
    Object? componentsSchemaPath = _copyWithUnset,
    Object? indexPath = _copyWithUnset,
    Object? indexSchemaPath = _copyWithUnset,
    Object? themesPath = _copyWithUnset,
    Object? themesSchemaPath = _copyWithUnset,
    Object? folderStructurePath = _copyWithUnset,
    Object? metaPath = _copyWithUnset,
    Object? themeConverterDartPath = _copyWithUnset,
    Object? installPath = _copyWithUnset,
    Object? sharedPath = _copyWithUnset,
    Object? includeReadme = _copyWithUnset,
    Object? includeMeta = _copyWithUnset,
    Object? includePreview = _copyWithUnset,
    Object? includeFiles = _copyWithUnset,
    Object? excludeFiles = _copyWithUnset,
    Object? capabilitySharedGroups = _copyWithUnset,
    Object? capabilityComposites = _copyWithUnset,
    Object? capabilityTheme = _copyWithUnset,
    Object? trustMode = _copyWithUnset,
    Object? trustSha256 = _copyWithUnset,
    Object? enabled = _copyWithUnset,
  }) {
    return RegistryConfigEntry(
      registryMode: _copyWithValue(registryMode, this.registryMode),
      registryPath: _copyWithValue(registryPath, this.registryPath),
      registryUrl: _copyWithValue(registryUrl, this.registryUrl),
      baseUrl: _copyWithValue(baseUrl, this.baseUrl),
      componentsPath: _copyWithValue(componentsPath, this.componentsPath),
      componentsSchemaPath:
          _copyWithValue(componentsSchemaPath, this.componentsSchemaPath),
      indexPath: _copyWithValue(indexPath, this.indexPath),
      indexSchemaPath: _copyWithValue(indexSchemaPath, this.indexSchemaPath),
      themesPath: _copyWithValue(themesPath, this.themesPath),
      themesSchemaPath: _copyWithValue(themesSchemaPath, this.themesSchemaPath),
      folderStructurePath:
          _copyWithValue(folderStructurePath, this.folderStructurePath),
      metaPath: _copyWithValue(metaPath, this.metaPath),
      themeConverterDartPath:
          _copyWithValue(themeConverterDartPath, this.themeConverterDartPath),
      installPath: _copyWithValue(installPath, this.installPath),
      sharedPath: _copyWithValue(sharedPath, this.sharedPath),
      includeReadme: _copyWithValue(includeReadme, this.includeReadme),
      includeMeta: _copyWithValue(includeMeta, this.includeMeta),
      includePreview: _copyWithValue(includePreview, this.includePreview),
      includeFiles: _copyWithValue(includeFiles, this.includeFiles),
      excludeFiles: _copyWithValue(excludeFiles, this.excludeFiles),
      capabilitySharedGroups:
          _copyWithValue(capabilitySharedGroups, this.capabilitySharedGroups),
      capabilityComposites:
          _copyWithValue(capabilityComposites, this.capabilityComposites),
      capabilityTheme: _copyWithValue(capabilityTheme, this.capabilityTheme),
      trustMode: _copyWithValue(trustMode, this.trustMode),
      trustSha256: _copyWithValue(trustSha256, this.trustSha256),
      enabled: _copyWithValue(enabled, this.enabled) ?? this.enabled,
    );
  }
}

T? _copyWithValue<T>(Object? value, T? current) {
  if (identical(value, _copyWithUnset)) {
    return current;
  }
  return value as T?;
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
