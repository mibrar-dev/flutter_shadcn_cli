import 'package:flutter_shadcn_cli/src/logger.dart';

/// What the installer would do with one file.
enum PlanAction {
  /// Destination absent: the file would be written.
  add,

  /// Destination present and different, and the caller allowed overwrites.
  update,

  /// Destination present and byte-identical: nothing to do.
  skip,

  /// User-owned file present: never overwritten (plan §1.5).
  keep;

  String get label => switch (this) {
        PlanAction.add => 'added',
        PlanAction.update => 'updated',
        PlanAction.skip => 'skipped',
        PlanAction.keep => 'kept',
      };
}

/// One file the installer considered, with its registry source and target.
class PlannedFile {
  const PlannedFile({
    required this.source,
    required this.target,
    required this.action,
    this.userOwned = false,
    this.reason,
    this.sha256,
  });

  /// Registry-relative source path.
  final String source;

  /// Project-relative destination path.
  final String target;

  final PlanAction action;

  /// True for `<name>_theme.dart` files the user owns.
  final bool userOwned;

  /// Why the action was chosen (`locally modified`, `identical`, ...).
  final String? reason;

  /// sha256 of the bytes that would be (or are) on disk.
  final String? sha256;

  Map<String, dynamic> toJson() {
    return {
      'source': source,
      'target': target,
      'action': action.name,
      'userOwned': userOwned,
      if (reason != null) 'reason': reason,
      if (sha256 != null) 'sha256': sha256,
    };
  }
}

/// A pub package the closure needs but the app pubspec does not declare.
class PlannedPackage {
  const PlannedPackage({
    required this.name,
    this.sdk = false,
    this.constraint,
  });

  final String name;
  final bool sdk;
  final String? constraint;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (sdk) 'sdk': true,
      if (constraint != null) 'constraint': constraint,
    };
  }
}

/// Outcome of `add`/`init`: the plan plus what was actually written.
class InstallReport {
  const InstallReport({
    required this.plan,
    required this.applied,
    this.written = const [],
    this.packagesAdded = const [],
  });

  final DryRunPlan plan;
  final bool applied;

  /// Project-relative paths written.
  final List<String> written;

  /// Package names added to `pubspec.yaml`.
  final List<String> packagesAdded;

  Map<String, dynamic> toJson() {
    return {
      'applied': applied,
      'written': written,
      'packagesAdded': packagesAdded,
      'plan': plan.toJson(),
    };
  }

  void writeHuman(CliLogger logger) {
    if (!applied) {
      plan.writeHuman(logger);
      return;
    }
    final summary = [
      '${plan.components.length} component(s)',
      if (plan.blocks.isNotEmpty) '${plan.blocks.length} block(s)',
    ].join(' + ');
    logger.header('Installed $summary');
    logger.info('  files written: ${written.length}');
    if (packagesAdded.isNotEmpty) {
      logger.info('  packages added: ${packagesAdded.join(', ')}');
    }
    final kept = plan.withAction(PlanAction.keep);
    if (kept.isNotEmpty) {
      logger.info('  user-owned files kept: ${kept.length}');
    }
  }
}

/// The full `add`/`init` plan: what would be added, updated, skipped or kept,
/// plus the pubspec deltas (plan §2.2 `--dry-run`).
class DryRunPlan {
  const DryRunPlan({
    required this.requested,
    this.missing = const [],
    this.requestedBlocks = const [],
    this.components = const [],
    this.blocks = const [],
    this.foundation = const [],
    this.theme = const [],
    this.primitives = const [],
    this.files = const [],
    this.packages = const [],
    this.includePreview = false,
  });

  /// Component ids the user asked for, in input order.
  final List<String> requested;

  /// Requested ids that are not in the manifest (empty: closure throws first).
  final List<String> missing;

  /// Block ids added on top of [requested], e.g. `add --all --blocks`.
  ///
  /// A block the user typed by name travels in [requested] instead: one
  /// address space serves `add <id>`, and such a block shows up in [blocks]
  /// like any other closure member.
  final List<String> requestedBlocks;

  final List<String> components;

  /// Block ids in the closure. Nothing depends on a block, so a block is never
  /// pulled in by another block: this is exactly what was asked for.
  final List<String> blocks;

  final List<String> foundation;
  final List<String> theme;
  final List<String> primitives;

  /// Every considered file, sorted by target.
  final List<PlannedFile> files;

  /// Missing pub packages the closure needs.
  final List<PlannedPackage> packages;

  final bool includePreview;

  List<PlannedFile> withAction(PlanAction action) =>
      files.where((file) => file.action == action).toList();

  int countOf(PlanAction action) => withAction(action).length;

  bool get hasChanges => files.any(
        (file) =>
            file.action == PlanAction.add || file.action == PlanAction.update,
      );

  Map<String, dynamic> toJson() {
    return {
      'requested': requested,
      'requestedBlocks': requestedBlocks,
      'missing': missing,
      'components': components,
      'blocks': blocks,
      'layers': {
        'foundation': foundation,
        'theme': theme,
        'primitives': primitives,
      },
      'includePreview': includePreview,
      'counts': {
        for (final action in PlanAction.values) action.label: countOf(action),
      },
      'files': files.map((file) => file.toJson()).toList(),
      'packages': packages.map((package) => package.toJson()).toList(),
    };
  }

  /// Human-readable plan, matching the v1 `dry-run` output shape.
  void writeHuman(CliLogger logger) {
    logger.header('Dry run: no files will be written');
    logger.section('Components (${components.length})');
    for (final id in components) {
      logger.info('  • $id');
    }
    if (blocks.isNotEmpty) {
      logger.section('Blocks (${blocks.length})');
      for (final id in blocks) {
        logger.info('  • $id');
      }
    }
    logger.section('Layers');
    logger.info('  foundation: ${foundation.join(', ')}');
    logger.info('  theme:      ${theme.join(', ')}');
    logger.info('  primitives: ${primitives.join(', ')}');
    if (includePreview) {
      logger.info('  previews:   included');
    }

    for (final action in PlanAction.values) {
      final entries = withAction(action);
      if (entries.isEmpty) {
        continue;
      }
      logger.section(
          '${action.label[0].toUpperCase()}${action.label.substring(1)} '
          '(${entries.length})');
      for (final file in entries) {
        final reason = file.reason == null ? '' : '  (${file.reason})';
        logger.info('  ${file.target}$reason');
      }
    }

    if (packages.isEmpty) {
      logger.section('Packages');
      logger.info('  all required packages already declared');
    } else {
      logger.section('Packages to add (${packages.length})');
      for (final package in packages) {
        final suffix =
            package.constraint == null ? '' : ' ${package.constraint}';
        logger.info('  ${package.name}$suffix');
      }
    }
  }
}
