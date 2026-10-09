import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_schema_validator.dart';

/// Block-level checks for the `components`, `themes` and `fileHashes` maps of
/// a registry manifest, plus the shared `files` / `packages` list checks.
///
/// Internal helper for [ManifestSchemaValidator] — split out to keep both
/// files small; not part of the public CLI API.
class ManifestComponentChecks {
  static const Set<String> _componentKeys = {
    'name',
    'category',
    'description',
    'entry',
    'files',
    'userOwned',
    'deps',
    'tags',
    'api',
    'theme',
    'install',
    'import',
    'packages',
  };

  static const Set<String> _componentDepKeys = {
    'foundation',
    'theme',
    'primitives',
    'components',
  };

  static const Set<String> _themeModes = {'light', 'dark'};

  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

  /// Validates the components map; returns id -> parsed entry maps.
  static Map<String, Map<String, dynamic>> checkComponents(
    Object? raw,
    Map<String, List<String>> foundation,
    Map<String, List<String>> theme,
    Map<String, List<String>> primitives,
    List<String> errors,
  ) {
    if (raw is! Map) {
      if (raw != null) errors.add('components: expected an object');
      return const {};
    }
    final entries = <String, Map<String, dynamic>>{};
    raw.forEach((key, value) {
      final id = key.toString();
      if (value is! Map) {
        errors.add('components.$id: expected an object');
        return;
      }
      entries[id] = value.map((k, v) => MapEntry(k.toString(), v));
    });

    for (final componentEntry in entries.entries) {
      final id = componentEntry.key;
      final json = componentEntry.value;
      for (final k in json.keys) {
        if (!_componentKeys.contains(k)) {
          errors.add('components.$id: unknown key "$k"');
        }
      }
      if (!ManifestSchemaValidator.idPattern.hasMatch(id)) {
        errors.add('components.$id: invalid component id');
      }
      for (final field in ['name', 'category', 'description']) {
        final value = json[field];
        if (value is! String || value.isEmpty) {
          errors.add('components.$id.$field: must be a non-empty string');
        }
      }
      final entry = json['entry'];
      if (entry is! String ||
          !ManifestSchemaValidator.relPathPattern.hasMatch(entry)) {
        errors.add('components.$id.entry: invalid relPath "$entry"');
      } else if (!entry.startsWith('components/$id/') ||
          !entry.endsWith('.dart')) {
        errors.add(
          'components.$id.entry: "$entry" is not components/$id/<file>.dart',
        );
      }
      final files = checkFiles(json['files'], 'components.$id.files', errors);
      for (final file in files) {
        if (!file.startsWith('components/$id/')) {
          errors.add(
            'components.$id.files: "$file" is not under components/$id/',
          );
        }
        if (file.endsWith('/preview.dart')) {
          errors.add(
            'components.$id.files: "$file" is preview.dart and must not be listed',
          );
        }
      }
      final userOwned = checkFiles(
        json['userOwned'],
        'components.$id.userOwned',
        errors,
      );
      for (final file in userOwned) {
        if (!file.startsWith('components/$id/')) {
          errors.add(
            'components.$id.userOwned: "$file" is not under components/$id/',
          );
        }
        if (!file.endsWith('_theme.dart')) {
          errors.add(
            'components.$id.userOwned: "$file" does not end with _theme.dart',
          );
        }
      }
      for (final file in userOwned) {
        if (files.contains(file)) {
          errors.add(
            'components.$id: "$file" is listed in both files and userOwned',
          );
        }
      }
      checkComponentDeps(
        json['deps'],
        id,
        foundation,
        theme,
        primitives,
        entries,
        errors,
      );
      checkTags(json['tags'], 'components.$id.tags', errors);
      checkApi(json['api'], 'components.$id.api', errors);
      final themeSection = json['theme'];
      if (themeSection != null && themeSection is! Map) {
        errors.add('components.$id.theme: expected an object or null');
      }
      checkPackages(json['packages'], 'components.$id.packages', errors);
    }
    return entries;
  }

  static void checkComponentDeps(
    Object? raw,
    String id,
    Map<String, List<String>> foundation,
    Map<String, List<String>> theme,
    Map<String, List<String>> primitives,
    Map<String, Map<String, dynamic>> components,
    List<String> errors,
  ) {
    if (raw == null) {
      errors.add('components.$id.deps: missing required object');
      return;
    }
    if (raw is! Map) {
      errors.add('components.$id.deps: expected an object');
      return;
    }
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    for (final key in json.keys) {
      if (!_componentDepKeys.contains(key)) {
        errors.add('components.$id.deps: unknown key "$key"');
      }
    }
    for (final key in _componentDepKeys) {
      if (!json.containsKey(key)) {
        errors.add('components.$id.deps: missing required key "$key"');
      }
    }
    void checkRefs(
      Object? value,
      String layer,
      String label,
      Map<String, Object?> known,
    ) {
      if (value is! List) {
        errors.add('components.$id.deps.$layer: expected an array');
        return;
      }
      for (final ref in value) {
        if (ref is! String) {
          errors.add('components.$id.deps.$layer: entries must be strings');
        } else if (!known.containsKey(ref)) {
          errors.add(
            'components.$id.deps.$layer: unknown $label id "$ref"',
          );
        }
      }
    }

    checkRefs(json['foundation'], 'foundation', 'foundation', foundation);
    checkRefs(json['theme'], 'theme', 'theme', theme);
    checkRefs(json['primitives'], 'primitives', 'primitive', primitives);
    checkRefs(json['components'], 'components', 'component', components);
  }

  static void checkTags(Object? raw, String path, List<String> errors) {
    if (raw is! List) {
      errors.add('$path: expected an array');
      return;
    }
    final seen = <String>{};
    for (final tag in raw) {
      if (tag is! String) {
        errors.add('$path: entries must be strings');
      } else if (!seen.add(tag)) {
        errors.add('$path: duplicate tag "$tag"');
      }
    }
  }

  static void checkApi(Object? raw, String path, List<String> errors) {
    if (raw == null) {
      errors.add('$path: missing required object');
      return;
    }
    if (raw is! Map) {
      errors.add('$path: expected an object');
      return;
    }
    raw.forEach((group, value) {
      if (value is List) {
        for (final name in value) {
          if (name is! String) {
            errors.add('$path.$group: entries must be strings');
          }
        }
      } else if (value is Map) {
        value.forEach((inner, names) {
          if (names is! List) {
            errors.add('$path.$group.$inner: expected an array');
            return;
          }
          for (final name in names) {
            if (name is! String) {
              errors.add('$path.$group.$inner: entries must be strings');
            }
          }
        });
      } else {
        errors.add(
          '$path.$group: expected a list of symbols or a named group of lists',
        );
      }
    });
  }

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

  static void checkFileHashes(
    Object? raw,
    Set<String> declaredFiles,
    List<String> errors,
  ) {
    if (raw is! Map) {
      if (raw != null) errors.add('fileHashes: expected an object');
      return;
    }
    final hashes = raw.map((key, value) => MapEntry(key.toString(), value));
    for (final entry in hashes.entries) {
      if (!ManifestSchemaValidator.relPathPattern.hasMatch(entry.key)) {
        errors.add('fileHashes: invalid relPath key "${entry.key}"');
      }
      if (entry.value is! String ||
          !_sha256Pattern.hasMatch(entry.value as String)) {
        errors.add(
          'fileHashes.${entry.key}: must be a lowercase sha256 hex digest',
        );
      }
    }
    for (final file in declaredFiles) {
      if (!hashes.containsKey(file)) {
        errors.add('fileHashes: missing entry for "$file"');
      }
    }
  }

  /// Validates a relPath list; returns the entries (including invalid ones,
  /// so callers can run further path checks without re-parsing).
  static List<String> checkFiles(
    Object? raw,
    String path,
    List<String> errors,
  ) {
    if (raw is! List) {
      errors.add('$path: expected an array');
      return const [];
    }
    final files = <String>[];
    final seen = <String>{};
    for (final entry in raw) {
      if (entry is! String) {
        errors.add('$path: entries must be strings');
        continue;
      }
      if (!ManifestSchemaValidator.relPathPattern.hasMatch(entry)) {
        errors.add('$path: invalid relPath "$entry"');
      } else if (entry.contains(r'\')) {
        errors.add('$path: "$entry" must use forward slashes');
      } else if (entry.split('/').contains('..')) {
        errors.add('$path: "$entry" must not contain ".." segments');
      } else if (!seen.add(entry)) {
        errors.add('$path: duplicate entry "$entry"');
      }
      files.add(entry);
    }
    return files;
  }

  static void checkPackages(Object? raw, String path, List<String> errors) {
    if (raw == null) {
      return;
    }
    if (raw is! List) {
      errors.add('$path: expected an array');
      return;
    }
    for (final entry in raw) {
      if (entry is! Map) {
        errors.add('$path: entries must be objects');
        continue;
      }
      final json = entry.map((k, v) => MapEntry(k.toString(), v));
      for (final key in json.keys) {
        if (!{'name', 'sdk', 'constraint'}.contains(key)) {
          errors.add('$path: unknown key "$key"');
        }
      }
      final name = json['name'];
      if (name is! String || name.isEmpty) {
        errors.add('$path.name: must be a non-empty string');
      }
      final sdk = json['sdk'];
      if (sdk != null && sdk is! bool) {
        errors.add('$path.sdk: must be a boolean');
      }
      final constraint = json['constraint'];
      if (constraint != null && constraint is! String) {
        errors.add('$path.constraint: must be a string');
      }
    }
  }
}
