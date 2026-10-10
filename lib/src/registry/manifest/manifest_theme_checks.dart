import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_schema_validator.dart';

/// Checks for the `themes` map of a registry manifest.
///
/// Internal helper for [ManifestSchemaValidator], split from
/// `ManifestComponentChecks` to keep both files small; not part of the public
/// CLI API.
class ManifestThemeChecks {
  static const Set<String> _themeModes = {'light', 'dark'};

  /// Validates the themes map; returns id -> parsed entry maps.
  static Map<String, Map<String, dynamic>> checkThemes(
    Object? raw,
    List<String> errors,
  ) {
    if (raw is! Map) {
      if (raw != null) errors.add('themes: expected an object');
      return const {};
    }
    final result = <String, Map<String, dynamic>>{};
    raw.forEach((key, value) {
      final id = key.toString();
      if (!ManifestSchemaValidator.idPattern.hasMatch(id)) {
        errors.add('themes.$id: invalid preset id');
      }
      if (value is! Map) {
        errors.add('themes.$id: expected an object');
        return;
      }
      final json = value.map((k, v) => MapEntry(k.toString(), v));
      for (final k in json.keys) {
        if (!{'file', 'name', 'modes'}.contains(k)) {
          errors.add('themes.$id: unknown key "$k"');
        }
      }
      final file = json['file'];
      if (file is! String ||
          !ManifestSchemaValidator.relPathPattern.hasMatch(file)) {
        errors.add('themes.$id.file: invalid relPath "$file"');
      } else if (!file.startsWith('themes/') || !file.endsWith('.json')) {
        errors.add('themes.$id.file: "$file" is not themes/<id>.json');
      }
      final name = json['name'];
      if (name is! String || name.isEmpty) {
        errors.add('themes.$id.name: must be a non-empty string');
      }
      final modes = json['modes'];
      if (modes is! List || modes.isEmpty) {
        errors.add('themes.$id.modes: expected a non-empty array');
        return;
      }
      final seen = <String>{};
      for (final mode in modes) {
        if (mode is! String || !_themeModes.contains(mode)) {
          errors.add('themes.$id.modes: invalid mode "$mode"');
        } else if (!seen.add(mode)) {
          errors.add('themes.$id.modes: duplicate mode "$mode"');
        }
      }
      result[id] = json;
    });
    return result;
  }
}
