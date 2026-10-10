import 'package:flutter_shadcn_cli/src/application/services/theme/app_theme_values.dart';
import 'package:flutter_shadcn_cli/src/registry/schema_validation_result.dart';

/// Validates a decoded theme preset (`lib/registry/themes/<id>.json`) against
/// `themes.schema.json` (schemaVersion 2) from the registry.
///
/// Hand-written for the same reason as `ManifestSchemaValidator`: the rules
/// mirror the JSON Schema exactly (same regexes, `additionalProperties: false`
/// as "unknown key" errors) but the schema file is not guaranteed to sit next
/// to a remote registry, and the CLI must reject a bad preset before it
/// reaches the generator.
///
/// Checks: required/unknown top-level keys, `schemaVersion == 2`, the id
/// pattern, all 32 colour tokens in BOTH `light` and `dark` with uppercase
/// `#RRGGBB`/`#RRGGBBAA` values, `radius >= 0`, `spacing > 0`, `tracking` with a
/// required `normal` step, the six shadow atoms per mode, the optional
/// `fonts` block and the `shadowsDerived` provenance enum.
class ThemePresetValidator {
  /// `amber-minimal`, matching the schema's `id` pattern.
  static final RegExp idPattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

  /// The schema's `colorToken` pattern: uppercase hex only.
  static final RegExp colorPattern = RegExp(r'^#[0-9A-F]{6}([0-9A-F]{2})?$');

  static const List<String> _requiredKeys = <String>[
    'id',
    'name',
    'schemaVersion',
    'light',
    'dark',
    'radius',
    'spacing',
    'tracking',
    'shadow',
  ];

  static const Set<String> _allowedKeys = <String>{
    ..._requiredKeys,
    r'$schema',
    'fonts',
    'shadowsDerived',
  };

  static const Set<String> _fontSlots = <String>{'sans', 'serif', 'mono'};

  static const Set<String> _trackingSteps = <String>{
    'normal',
    'tight',
    'wide',
  };

  static const List<String> _shadowAtoms = <String>[
    'color',
    'opacity',
    'blur',
    'spread',
    'offsetX',
    'offsetY',
  ];

  static const Set<String> _shadowsDerived = <String>{'cli', 'from-legacy'};

  /// Validates [preset]. [label] is used in error messages (a path or a
  /// registry-relative `themes/<id>.json`).
  static SchemaValidationResult validate(
    Map<String, dynamic> preset, {
    String label = 'theme preset',
  }) {
    final errors = <String>[];

    for (final key in _requiredKeys) {
      if (!preset.containsKey(key)) {
        errors.add('$label: missing required key "$key".');
      }
    }
    for (final key in preset.keys) {
      if (!_allowedKeys.contains(key)) {
        errors.add('$label: unknown key "$key".');
      }
    }
    if (errors.isNotEmpty) {
      return SchemaValidationResult(isValid: false, errors: errors);
    }

    final id = preset['id'];
    if (id is! String || !idPattern.hasMatch(id)) {
      errors.add('$label: "id" must match ${idPattern.pattern} (got $id).');
    }
    final name = preset['name'];
    if (name is! String || name.isEmpty) {
      errors.add('$label: "name" must be a non-empty string (got $name).');
    }
    if (preset['schemaVersion'] != 2) {
      errors.add(
        '$label: "schemaVersion" must be 2 (got ${preset['schemaVersion']}).',
      );
    }
    final derived = preset['shadowsDerived'];
    if (derived != null && !_shadowsDerived.contains('$derived')) {
      errors.add(
        '$label: "shadowsDerived" must be one of '
        '${_shadowsDerived.join(', ')} (got $derived).',
      );
    }

    _checkColors(preset['light'], 'light', errors, label);
    _checkColors(preset['dark'], 'dark', errors, label);
    _checkFonts(preset['fonts'], errors, label);
    _checkNonNegative(preset['radius'], 'radius', errors, label);
    _checkPositive(preset['spacing'], 'spacing', errors, label);
    _checkTracking(preset['tracking'], errors, label);
    _checkShadow(preset['shadow'], errors, label);

    return SchemaValidationResult(isValid: errors.isEmpty, errors: errors);
  }

  static void _checkColors(
    Object? raw,
    String mode,
    List<String> errors,
    String label,
  ) {
    if (raw is! Map) {
      errors.add('$label: "$mode" must be an object (got $raw).');
      return;
    }
    final map = raw.map((key, value) => MapEntry('$key', value));
    for (final key in appThemeColorTokenKeys) {
      final value = map[key];
      if (value == null) {
        errors.add('$label: "$mode.$key" is required.');
        continue;
      }
      if (value is! String || !colorPattern.hasMatch(value)) {
        errors.add(
          '$label: "$mode.$key" must be #RRGGBB or #RRGGBBAA in upper case '
          '(got $value).',
        );
      }
    }
    for (final key in map.keys) {
      if (!appThemeColorTokenKeys.contains(key)) {
        errors.add('$label: "$mode" has unknown token "$key".');
      }
    }
  }

  static void _checkFonts(
    Object? raw,
    List<String> errors,
    String label,
  ) {
    if (raw == null) {
      return;
    }
    if (raw is! Map) {
      errors.add('$label: "fonts" must be an object (got $raw).');
      return;
    }
    if (raw.isEmpty) {
      errors.add('$label: "fonts" must name at least one family.');
      return;
    }
    raw.forEach((key, value) {
      final slot = '$key';
      if (!_fontSlots.contains(slot)) {
        errors.add('$label: "fonts" has unknown slot "$slot".');
      }
      if (value is! String || value.isEmpty) {
        errors.add('$label: "fonts.$slot" must be a non-empty string.');
      }
    });
  }

  static void _checkTracking(
    Object? raw,
    List<String> errors,
    String label,
  ) {
    if (raw is! Map) {
      errors.add('$label: "tracking" must be an object (got $raw).');
      return;
    }
    final map = raw.map((key, value) => MapEntry('$key', value));
    if (!map.containsKey('normal')) {
      errors.add('$label: "tracking.normal" is required.');
    }
    map.forEach((key, value) {
      if (!_trackingSteps.contains(key)) {
        errors.add('$label: "tracking" has unknown step "$key".');
      }
      if (value is! num) {
        errors.add('$label: "tracking.$key" must be a number (got $value).');
      }
    });
  }

  static void _checkShadow(
    Object? raw,
    List<String> errors,
    String label,
  ) {
    if (raw is! Map) {
      errors.add('$label: "shadow" must be an object (got $raw).');
      return;
    }
    for (final mode in const ['light', 'dark']) {
      final atoms = raw[mode];
      if (atoms is! Map) {
        errors.add('$label: "shadow.$mode" must be an object (got $atoms).');
        continue;
      }
      final map = atoms.map((key, value) => MapEntry('$key', value));
      for (final atom in _shadowAtoms) {
        final value = map[atom];
        if (value == null) {
          errors.add('$label: "shadow.$mode.$atom" is required.');
          continue;
        }
        if (atom == 'color') {
          if (value is! String || !colorPattern.hasMatch(value)) {
            errors.add(
              '$label: "shadow.$mode.color" must be #RRGGBB or #RRGGBBAA '
              '(got $value).',
            );
          }
          continue;
        }
        if (value is! num) {
          errors.add(
            '$label: "shadow.$mode.$atom" must be a number (got $value).',
          );
        }
      }
      for (final key in map.keys) {
        if (!_shadowAtoms.contains(key)) {
          errors.add('$label: "shadow.$mode" has unknown atom "$key".');
        }
      }
      final opacity = map['opacity'];
      if (opacity is num && (opacity < 0 || opacity > 1)) {
        errors.add('$label: "shadow.$mode.opacity" must be within 0..1.');
      }
      final blur = map['blur'];
      if (blur is num && blur < 0) {
        errors.add('$label: "shadow.$mode.blur" must be >= 0.');
      }
    }
    for (final key in raw.keys) {
      if (key != 'light' && key != 'dark') {
        errors.add('$label: "shadow" has unknown mode "$key".');
      }
    }
  }

  static void _checkNonNegative(
    Object? raw,
    String key,
    List<String> errors,
    String label,
  ) {
    if (raw is! num) {
      errors.add('$label: "$key" must be a number (got $raw).');
      return;
    }
    if (raw < 0) errors.add('$label: "$key" must be >= 0 (got $raw).');
  }

  static void _checkPositive(
    Object? raw,
    String key,
    List<String> errors,
    String label,
  ) {
    if (raw is! num) {
      errors.add('$label: "$key" must be a number (got $raw).');
      return;
    }
    if (raw <= 0) errors.add('$label: "$key" must be > 0 (got $raw).');
  }
}
