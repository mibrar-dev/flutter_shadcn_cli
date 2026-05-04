class ThemeIndexEntry {
  final String id;
  final String name;
  final String file;
  final List<Map<String, dynamic>> files;
  final Map<String, dynamic>? preview;

  const ThemeIndexEntry({
    required this.id,
    required this.name,
    this.file = '',
    this.files = const [],
    this.preview,
  });

  factory ThemeIndexEntry.fromJson(Map<String, dynamic> json) {
    return ThemeIndexEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      file: json['file']?.toString() ?? '',
      files: (json['files'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) =>
              entry.map((key, value) => MapEntry(key.toString(), value)))
          .toList(),
      preview: (json['preview'] as Map?)?.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
  }

  bool get isValid =>
      id.trim().isNotEmpty && (file.trim().isNotEmpty || files.isNotEmpty);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (file.isNotEmpty) 'file': file,
      if (files.isNotEmpty) 'files': files,
      if (preview != null) 'preview': preview,
    };
  }
}
