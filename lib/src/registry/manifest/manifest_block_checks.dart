import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_block.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_component_checks.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_schema_validator.dart';

/// Checks for the `blocks` map of a registry manifest (P6-B1 layer 4).
///
/// Internal helper for [ManifestSchemaValidator], split from
/// `ManifestComponentChecks` to keep both files small; not part of the public
/// CLI API.
class ManifestBlockChecks {
  /// Keys of a `blocks.<id>` entry (P6-B1). A block has no `api` (it declares
  /// no reusable symbols), no `userOwned` (nothing is user-editable) and no
  /// `theme` (its components own their themes); it adds `docs`, the markdown
  /// the CLI never copies.
  static const Set<String> _blockKeys = {
    'name',
    'category',
    'description',
    'viewport',
    'entry',
    'files',
    'docs',
    'deps',
    'tags',
    'install',
    'import',
    'packages',
  };

  /// Validates the `blocks` map (registry layer 4); returns id -> parsed
  /// entry maps.
  ///
  /// Absent `blocks` is valid: a registry written before the layer existed
  /// has none. When present, a block id must not also be a component id (the
  /// two namespaces share one address space for `add <id>`), its `files` are
  /// Dart only, its `docs` are markdown only, and `deps.components` may name
  /// components only — never another block.
  static Map<String, Map<String, dynamic>> checkBlocks(
    Object? raw,
    Map<String, List<String>> foundation,
    Map<String, List<String>> theme,
    Map<String, List<String>> primitives,
    Map<String, Map<String, dynamic>> components,
    List<String> errors,
  ) {
    if (raw == null) {
      return const {};
    }
    if (raw is! Map) {
      errors.add('blocks: expected an object');
      return const {};
    }
    final entries = <String, Map<String, dynamic>>{};
    raw.forEach((key, value) {
      final id = key.toString();
      if (value is! Map) {
        errors.add('blocks.$id: expected an object');
        return;
      }
      entries[id] = value.map((k, v) => MapEntry(k.toString(), v));
    });

    for (final entry in entries.entries) {
      final id = entry.key;
      final json = entry.value;
      for (final k in json.keys) {
        if (!_blockKeys.contains(k)) {
          errors.add('blocks.$id: unknown key "$k"');
        }
      }
      if (!ManifestSchemaValidator.idPattern.hasMatch(id)) {
        errors.add('blocks.$id: invalid block id');
      }
      if (components.containsKey(id)) {
        errors.add(
          'blocks.$id: the id is already a component; blocks and components '
          'share one address space',
        );
      }
      for (final field in ['name', 'category', 'description']) {
        final value = json[field];
        if (value is! String || value.isEmpty) {
          errors.add('blocks.$id.$field: must be a non-empty string');
        }
      }
      final viewport = json['viewport'];
      if (viewport is! String || !manifestBlockViewports.contains(viewport)) {
        errors.add(
          'blocks.$id.viewport: must be one of '
          '${manifestBlockViewports.join(', ')} (got "$viewport")',
        );
      }
      final entryPath = json['entry'];
      if (entryPath is! String ||
          !ManifestSchemaValidator.relPathPattern.hasMatch(entryPath)) {
        errors.add('blocks.$id.entry: invalid relPath "$entryPath"');
      } else if (!entryPath.startsWith('blocks/$id/') ||
          !entryPath.endsWith('.dart')) {
        errors.add(
          'blocks.$id.entry: "$entryPath" is not blocks/$id/<file>.dart',
        );
      }
      final files = ManifestComponentChecks.checkFiles(
          json['files'], 'blocks.$id.files', errors);
      for (final file in files) {
        if (!file.startsWith('blocks/$id/')) {
          errors.add('blocks.$id.files: "$file" is not under blocks/$id/');
        } else if (!file.endsWith('.dart')) {
          errors.add('blocks.$id.files: "$file" is not a Dart file');
        }
      }
      final docs = ManifestComponentChecks.checkDocs(
          json['docs'], 'blocks.$id.docs', errors);
      for (final doc in docs) {
        if (!doc.startsWith('blocks/$id/')) {
          errors.add('blocks.$id.docs: "$doc" is not under blocks/$id/');
        }
      }
      ManifestComponentChecks.checkComponentDeps(
        json['deps'],
        id,
        foundation,
        theme,
        primitives,
        components,
        errors,
        label: 'blocks',
      );
      ManifestComponentChecks.checkTags(
          json['tags'], 'blocks.$id.tags', errors);
      for (final key in const ['install', 'import']) {
        final value = json[key];
        if (value != null && value is! String) {
          errors.add('blocks.$id.$key: must be a string');
        }
      }
      ManifestComponentChecks.checkPackages(
          json['packages'], 'blocks.$id.packages', errors);
    }
    return entries;
  }
}
