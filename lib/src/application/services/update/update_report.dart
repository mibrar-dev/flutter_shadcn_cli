import 'package:flutter_shadcn_cli/src/logger.dart';

/// Outcome of `update` (P5_CLI_PLAN.md §2.3).
class UpdateReport {
  const UpdateReport({
    this.added = const [],
    this.updated = const [],
    this.modified = const [],
    this.removedUpstream = const [],
    this.missing = const [],
    this.unchanged = const [],
    this.packagesAdded = const [],
    this.themeRegenerated = false,
    this.applied = true,
  });

  /// New registry files the manifest now declares for an installed component
  /// (or one of its deps) and that were not installed before.
  final List<String> added;

  /// Registry-owned files overwritten with the manifest's current bytes.
  final List<String> updated;

  /// Files edited on disk: reported and skipped, never overwritten.
  final List<String> modified;

  /// Files the lock tracks that the manifest no longer declares.
  final List<String> removedUpstream;

  /// Files the lock tracks that are missing from disk and were restored.
  final List<String> missing;

  /// Files already identical to the manifest.
  final List<String> unchanged;

  /// Pub packages the closure needs that were missing from `pubspec.yaml`.
  final List<String> packagesAdded;

  final bool themeRegenerated;

  final bool applied;

  /// True when the install is behind, drifted or incomplete.
  bool get needsAttention =>
      added.isNotEmpty ||
      updated.isNotEmpty ||
      modified.isNotEmpty ||
      removedUpstream.isNotEmpty ||
      packagesAdded.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'applied': applied,
        'themeRegenerated': themeRegenerated,
        'added': added,
        'updated': updated,
        'modified': modified,
        'removedUpstream': removedUpstream,
        'missing': missing,
        'packagesAdded': packagesAdded,
        'unchangedCount': unchanged.length,
        'needsAttention': needsAttention,
      };

  void writeHuman(CliLogger logger) {
    if (!needsAttention) {
      logger.success('Everything is up to date.');
    }
    if (added.isNotEmpty) {
      logger.success('Added ${added.length} new file(s).');
    }
    if (updated.isNotEmpty) {
      logger.success('Updated ${updated.length} file(s).');
    }
    if (missing.isNotEmpty) {
      logger.warn('Restored ${missing.length} missing file(s).');
    }
    if (packagesAdded.isNotEmpty) {
      logger.info('Added packages: ${packagesAdded.join(', ')}');
    }
    if (modified.isNotEmpty) {
      logger.warn(
        'Skipped ${modified.length} locally modified file(s): '
        '${modified.take(5).join(', ')}'
        '${modified.length > 5 ? ' …' : ''}',
      );
    }
    if (removedUpstream.isNotEmpty) {
      logger.warn(
        '${removedUpstream.length} file(s) were removed upstream and left '
        'in place: ${removedUpstream.take(5).join(', ')}'
        '${removedUpstream.length > 5 ? ' …' : ''}',
      );
    }
  }
}
