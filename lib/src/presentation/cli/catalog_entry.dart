import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_block.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_component.dart';

/// What a `list`/`search` row describes.
enum CatalogKind {
  component('component'),
  block('block');

  const CatalogKind(this.name);

  final String name;
}

/// One row of the `list` / `search` catalog: a component or a block, both
/// carrying the category P6-B1 put in `meta.json`.
class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.tags,
    required this.kind,
    this.viewport,
  });

  factory CatalogEntry.component(ManifestComponent component) => CatalogEntry(
        id: component.id,
        name: component.name,
        category: component.category,
        description: component.description,
        tags: component.tags,
        kind: CatalogKind.component,
      );

  factory CatalogEntry.block(ManifestBlock block) => CatalogEntry(
        id: block.id,
        name: block.name,
        category: block.category,
        description: block.description,
        tags: block.tags,
        kind: CatalogKind.block,
        viewport: block.viewport,
      );

  final String id;
  final String name;
  final String category;
  final String description;
  final List<String> tags;

  final CatalogKind kind;

  /// Blocks only: `desktop` or `mobile`.
  final String? viewport;

  /// True when [query] matches id, name, description or a tag
  /// (case-insensitive, as `search` has always done).
  bool matches(String query) {
    final needle = query.toLowerCase();
    if (id.toLowerCase().contains(needle) ||
        name.toLowerCase().contains(needle) ||
        description.toLowerCase().contains(needle)) {
      return true;
    }
    return tags.any((tag) => tag.toLowerCase().contains(needle));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'category': category,
        'description': description,
        'tags': tags,
        if (viewport != null) 'viewport': viewport,
      };
}

/// `--category` filter: a case-insensitive exact match, so
/// `--category layout` finds "Layout" without matching "Layout & Grid".
List<CatalogEntry> filterByCategory(
  Iterable<CatalogEntry> entries,
  String? category,
) {
  final wanted = category?.trim();
  if (wanted == null || wanted.isEmpty) {
    return entries.toList();
  }
  final needle = wanted.toLowerCase();
  return entries
      .where((entry) => entry.category.toLowerCase() == needle)
      .toList();
}

/// Groups [entries] by category: categories sorted alphabetically, entries by
/// id inside each group. The order is stable so human and JSON output never
/// shuffle between runs.
Map<String, List<CatalogEntry>> groupByCategory(
  Iterable<CatalogEntry> entries,
) {
  final grouped = <String, List<CatalogEntry>>{};
  for (final entry in entries) {
    grouped.putIfAbsent(entry.category, () => <CatalogEntry>[]).add(entry);
  }
  final sorted = grouped.keys.toList()..sort();
  return {
    for (final category in sorted)
      category: (grouped[category]!..sort((a, b) => a.id.compareTo(b.id))),
  };
}

/// Sorted id list for a JSON summary of the categories on show.
List<Map<String, dynamic>> categorySummary(
  Iterable<CatalogEntry> entries,
) {
  return [
    for (final entry in groupByCategory(entries).entries)
      {'category': entry.key, 'count': entry.value.length},
  ];
}

/// Writes the grouped human listing, e.g.
/// `  Forms & Inputs (2):` followed by one padded row per entry.
void writeGroupedCatalog(
  Iterable<CatalogEntry> entries, {
  required void Function(String line) write,
}) {
  for (final group in groupByCategory(entries).entries) {
    write('${group.key} (${group.value.length}):');
    for (final entry in group.value) {
      final suffix = entry.viewport == null ? '' : '  [${entry.viewport}]';
      write('  ${entry.id.padRight(28)} ${entry.description}$suffix');
    }
  }
}
