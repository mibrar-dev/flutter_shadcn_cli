class IndexComponent {
  final String id;
  final String name;
  final String category;
  final String description;
  final List<String> tags;
  final String install;
  final String import_;
  final String importPath;
  final Map<String, dynamic> api;
  final Map<String, dynamic> examples;
  final Map<String, dynamic> dependencies;
  final List<String> related;

  const IndexComponent({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.tags,
    required this.install,
    required this.import_,
    required this.importPath,
    required this.api,
    required this.examples,
    required this.dependencies,
    required this.related,
  });

  factory IndexComponent.fromJson(Map<String, dynamic> json) {
    return IndexComponent(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      description: json['description'] as String,
      tags: List<String>.from(json['tags'] as List? ?? []),
      install: json['install'] as String? ?? '',
      import_: normalizeImportStatement(json['import'] as String? ?? ''),
      importPath: normalizeImportPath(json['importPath'] as String? ?? ''),
      api: json['api'] as Map<String, dynamic>? ?? {},
      examples: json['examples'] as Map<String, dynamic>? ?? {},
      dependencies: json['dependencies'] as Map<String, dynamic>? ?? {},
      related: List<String>.from(json['related'] as List? ?? []),
    );
  }

  IndexComponent copyWith({
    String? id,
    String? name,
    String? category,
    String? description,
    List<String>? tags,
    String? install,
    String? import_,
    String? importPath,
    Map<String, dynamic>? api,
    Map<String, dynamic>? examples,
    Map<String, dynamic>? dependencies,
    List<String>? related,
  }) {
    return IndexComponent(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      install: install ?? this.install,
      import_: import_ ?? this.import_,
      importPath: importPath ?? this.importPath,
      api: api ?? this.api,
      examples: examples ?? this.examples,
      dependencies: dependencies ?? this.dependencies,
      related: related ?? this.related,
    );
  }

  /// Normalizes a registry-authored install-relative path such as
  /// `ui/shadcn/control/button/button.dart` to the real install layout
  /// `ui/shadcn/components/control/button/button.dart`.
  ///
  /// Older registry entries omit the `components` segment even though
  /// components install under `{installPath}/components/...`. The
  /// normalization is idempotent: paths that already contain the segment
  /// are returned unchanged, as are paths outside the known `ui/shadcn`
  /// install root (other registries may use a different layout).
  static String normalizeImportPath(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    final segments = trimmed.split('/');
    if (segments.length >= 3 &&
        segments[0] == 'ui' &&
        segments[1] == 'shadcn' &&
        segments[2] != 'components') {
      return 'ui/shadcn/components/${segments.sublist(2).join('/')}';
    }
    if (segments.length >= 4 &&
        segments[0] == 'lib' &&
        segments[1] == 'ui' &&
        segments[2] == 'shadcn' &&
        segments[3] != 'components') {
      return 'lib/ui/shadcn/components/${segments.sublist(3).join('/')}';
    }
    return trimmed;
  }

  /// Applies [normalizeImportPath] to the path embedded in a Dart import
  /// statement such as
  /// `import 'package:<your_app>/ui/shadcn/control/button/button.dart';`.
  /// Statements without a recognizable embedded path are returned unchanged.
  static String normalizeImportStatement(String raw) {
    final pattern = RegExp(r"^(import\s+'package:[^'/]+/)([^']+)(';\s*)$");
    final match = pattern.firstMatch(raw.trim());
    if (match == null) {
      return raw;
    }
    final embedded = match.group(2) ?? '';
    final normalized = normalizeImportPath(embedded);
    if (normalized == embedded) {
      return raw;
    }
    return '${match.group(1)}$normalized${match.group(3)}';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'description': description,
      'tags': tags,
      'install': install,
      'import': import_,
      'importPath': importPath,
      'api': api,
      'examples': examples,
      'dependencies': dependencies,
      'related': related,
    };
  }

  bool matches(String query) {
    final lower = query.toLowerCase();
    return id.contains(lower) ||
        name.toLowerCase().contains(lower) ||
        description.toLowerCase().contains(lower) ||
        tags.any((tag) => tag.toLowerCase().contains(lower)) ||
        related.any((rel) => rel.toLowerCase().contains(lower));
  }

  int relevanceScore(String query) {
    final lower = query.toLowerCase();
    var score = 0;

    if (id.toLowerCase() == lower) score += 100;
    if (id.toLowerCase().contains(lower)) score += 50;
    if (name.toLowerCase() == lower) score += 80;
    if (name.toLowerCase().contains(lower)) score += 40;
    if (tags.contains(lower)) score += 60;
    if (description.toLowerCase().contains(lower)) score += 10;

    return score;
  }
}
