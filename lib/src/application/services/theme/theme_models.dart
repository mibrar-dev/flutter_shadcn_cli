import 'package:flutter_shadcn_cli/src/registry/manifest/theme_preset.dart';

/// One row of `theme list`, built from the manifest `themes` map.
class ThemeCatalogEntry {
  const ThemeCatalogEntry({
    required this.id,
    required this.name,
    required this.modes,
    required this.file,
    this.isCurrent = false,
  });

  /// Preset id, e.g. `vercel`; also the key of the manifest `themes` map.
  final String id;

  /// Human readable preset name, e.g. `Vercel`.
  final String name;

  /// Brightness modes the preset defines (`light`, `dark`).
  final List<String> modes;

  /// Registry-relative preset file, `themes/<id>.json`.
  final String file;

  /// True when this preset is the one recorded in `shadcn.lock`.
  final bool isCurrent;

  /// True when the preset defines a dark palette.
  bool get supportsDark => modes.contains('dark');

  /// Builds a row, marking [currentId] (if any) as the active preset.
  static ThemeCatalogEntry fromPreset(
    ThemePreset preset, {
    String? currentId,
  }) {
    return ThemeCatalogEntry(
      id: preset.id,
      name: preset.name,
      modes: List.unmodifiable(preset.modes),
      file: preset.file,
      isCurrent: currentId != null &&
          currentId.isNotEmpty &&
          currentId.toLowerCase() == preset.id.toLowerCase(),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'modes': modes,
        'file': file,
        'current': isCurrent,
      };
}

/// What `theme apply` did with `<installRoot>/theme/app_theme.dart`.
enum ThemeApplyStatus {
  /// The file did not exist and was written.
  created,

  /// The file existed, was locally modified (or untracked) and `--refresh`
  /// was given, so it was overwritten.
  refreshed,

  /// The file already matched the lock and was left untouched.
  unchanged,

  /// The file differed from the lock and `--refresh` was NOT given, so
  /// nothing was written.
  drift,
}

/// Why a generated theme file counts as drifted.
enum ThemeDriftKind {
  /// The bytes on disk differ from the hash recorded in `shadcn.lock`.
  modified,

  /// The file exists but `shadcn.lock` has no `theme` entry for it, so the
  /// CLI cannot tell whether it is generated or hand-written.
  untracked,
}

/// Drift detail attached to a [ThemeApplyStatus.drift] result.
class ThemeDrift {
  const ThemeDrift({
    required this.kind,
    required this.path,
    this.recordedSha256,
    this.actualSha256,
  });

  final ThemeDriftKind kind;

  /// Project-relative path of the generated file.
  final String path;

  /// sha256 recorded in `shadcn.lock`, when the lock knows the file.
  final String? recordedSha256;

  /// sha256 of the bytes currently on disk.
  final String? actualSha256;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'path': path,
        'recordedSha256': recordedSha256,
        'actualSha256': actualSha256,
      };
}

/// Outcome of `theme apply <preset>`.
class ThemeApplyResult {
  const ThemeApplyResult({
    required this.status,
    required this.presetId,
    required this.presetName,
    required this.path,
    required this.sha256,
    required this.sourceFile,
    this.drift,
  });

  final ThemeApplyStatus status;
  final String presetId;
  final String presetName;

  /// Project-relative path of the generated file.
  final String path;

  /// sha256 of the rendered file (recorded in `shadcn.lock`).
  final String sha256;

  /// Registry-relative preset JSON the file was rendered from.
  final String sourceFile;

  final ThemeDrift? drift;

  /// True when the file on disk now matches the lock.
  bool get isClean => status != ThemeApplyStatus.drift;

  Map<String, Object?> toJson() => <String, Object?>{
        'status': status.name,
        'presetId': presetId,
        'presetName': presetName,
        'path': path,
        'sha256': sha256,
        'source': sourceFile,
        if (drift != null) 'drift': drift!.toJson(),
      };
}

/// A theme operation could not be completed: unknown preset, unreadable
/// registry, or a preset that fails `themes.schema.json`.
class ThemeApplyException implements Exception {
  const ThemeApplyException(this.message, {this.details = const []});

  final String message;
  final List<String> details;

  /// All lines, ready to print one per line.
  List<String> get lines => <String>[message, ...details];

  @override
  String toString() => details.isEmpty
      ? 'ThemeApplyException: $message'
      : 'ThemeApplyException: $message\n${details.join('\n')}';
}
