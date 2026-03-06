class WidgetThemeTargetEntry {
  final String id;
  final String label;
  final String? schemaPath;
  final String? configPath;
  final Map<String, dynamic>? uiHints;
  final bool isDefault;

  const WidgetThemeTargetEntry({
    required this.id,
    required this.label,
    this.schemaPath,
    this.configPath,
    this.uiHints,
    this.isDefault = false,
  });

  factory WidgetThemeTargetEntry.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? json['themeType']?.toString() ?? '';
    final label = json['label']?.toString() ?? json['name']?.toString() ?? id;
    return WidgetThemeTargetEntry(
      id: id,
      label: label,
      schemaPath: json['schemaPath']?.toString(),
      configPath: json['configPath']?.toString(),
      uiHints: (json['uiHints'] as Map?)?.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      isDefault: json['default'] == true || json['isDefault'] == true,
    );
  }

  bool get isValid => id.trim().isNotEmpty;
}
