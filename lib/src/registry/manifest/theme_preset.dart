/// A theme preset entry from the manifest `themes` map (42 presets
/// post-cutover). The map key is the preset id; [file] points at the
/// canonical schemaVersion 2 preset JSON under `themes/`.
class ThemePreset {
  final String id;
  final String file;
  final String name;
  final List<String> modes;

  const ThemePreset({
    required this.id,
    required this.file,
    required this.name,
    required this.modes,
  });

  factory ThemePreset.fromJson(String id, Map<String, dynamic> json) {
    return ThemePreset(
      id: id,
      file: json['file'] as String? ?? '',
      name: json['name'] as String? ?? '',
      modes: json['modes'] is List
          ? (json['modes'] as List).map((entry) => entry.toString()).toList()
          : const [],
    );
  }

  bool get isDark => modes.contains('dark');
}
