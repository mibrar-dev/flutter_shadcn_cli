import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/pubspec/pubspec_change_planner.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_unit.dart';
import 'package:path/path.dart' as p;

/// A pub package the manifest says a unit needs (plan §9.1).
///
/// Derived by the kit generator from the unit's `package:` imports;
/// `flutter_localizations` arrives with `sdk: true`.
class PubPackageRequirement {
  const PubPackageRequirement({
    required this.name,
    this.sdk = false,
    this.constraint,
  });

  factory PubPackageRequirement.fromPackageRef(PackageRef ref) {
    return PubPackageRequirement(
      name: ref.name,
      sdk: ref.sdk,
      constraint: ref.constraint,
    );
  }

  final String name;
  final bool sdk;
  final String? constraint;

  /// Value written under the package key in `pubspec.yaml`.
  Object get pubspecValue =>
      sdk ? {'sdk': constraint ?? 'flutter'} : (constraint ?? 'any');

  String get display {
    if (sdk) {
      return '$name (sdk: ${constraint ?? 'flutter'})';
    }
    return constraint == null ? name : '$name $constraint';
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (sdk) 'sdk': true,
      if (constraint != null) 'constraint': constraint,
    };
  }
}

/// Runs the real pub tooling; injected so tests never shell out.
abstract class PubCommandRunner {
  Future<void> pubGet(String projectRoot);

  Future<void> pubAdd(String projectRoot, Iterable<String> packages);
}

/// [PubCommandRunner] backed by `flutter pub ...`.
class ProcessPubCommandRunner implements PubCommandRunner {
  const ProcessPubCommandRunner({this.executable = 'flutter'});

  final String executable;

  @override
  Future<void> pubGet(String projectRoot) =>
      _run(projectRoot, const ['pub', 'get']);

  @override
  Future<void> pubAdd(String projectRoot, Iterable<String> packages) =>
      _run(projectRoot, ['pub', 'add', ...packages]);

  Future<void> _run(String projectRoot, List<String> args) async {
    final result = await Process.run(
      executable,
      args,
      workingDirectory: projectRoot,
    );
    if (result.exitCode != 0) {
      throw PubCommandException(
        executable: executable,
        args: args,
        exitCode: result.exitCode,
        stderr: result.stderr.toString(),
      );
    }
  }
}

/// A `pub get`/`pub add` invocation failed.
class PubCommandException implements Exception {
  const PubCommandException({
    required this.executable,
    required this.args,
    required this.exitCode,
    required this.stderr,
  });

  final String executable;
  final List<String> args;
  final int exitCode;
  final String stderr;

  @override
  String toString() =>
      '$executable ${args.join(' ')} failed ($exitCode): ${stderr.trim()}';
}

/// Result of comparing the closure's package requirements with `pubspec.yaml`.
class PubspecPackagePlan {
  const PubspecPackagePlan({
    this.missing = const [],
    this.present = const [],
    this.conflicts = const [],
    this.updatedLines,
  });

  /// Packages to add to `dependencies:`.
  final List<PubPackageRequirement> missing;

  /// Packages already declared (matching or compatible constraint).
  final List<String> present;

  /// Packages declared with an incompatible constraint (never overwritten).
  final List<PubspecDependencyConflict> conflicts;

  /// The edited pubspec lines when [missing] is non-empty and no conflicts.
  final List<String>? updatedLines;

  /// True when there is a pubspec edit to apply: at least one missing package,
  /// no conflict and an edited document (a missing pubspec cannot be edited).
  bool get hasChanges =>
      missing.isNotEmpty && conflicts.isEmpty && updatedLines != null;

  Map<String, dynamic> toJson() {
    return {
      'missing': missing.map((package) => package.toJson()).toList(),
      'present': present,
      'conflicts': conflicts
          .map(
            (conflict) => {
              'package': conflict.package,
              'existing': conflict.existing?.toString(),
              'requested': conflict.requested?.toString(),
            },
          )
          .toList(),
    };
  }
}

/// Computes and applies the pubspec deltas for the closure's packages.
///
/// Writing uses the line-preserving [PubspecChangePlanner]; the actual
/// `pub get` goes through the injectable [PubCommandRunner].
class PubPackageResolver {
  const PubPackageResolver({
    required this.projectRoot,
    required this.runner,
    this.logger,
    this.planner = const PubspecChangePlanner(),
  });

  final String projectRoot;
  final PubCommandRunner runner;
  final CliLogger? logger;
  final PubspecChangePlanner planner;

  File get _pubspec => File(p.join(projectRoot, 'pubspec.yaml'));

  /// Computes the delta without touching the filesystem.
  Future<PubspecPackagePlan> plan(
    Iterable<PubPackageRequirement> required,
  ) async {
    final requirements = required.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (requirements.isEmpty) {
      return const PubspecPackagePlan();
    }
    if (!_pubspec.existsSync()) {
      return PubspecPackagePlan(missing: requirements);
    }
    final lines = _pubspec.readAsStringSync().split('\n');
    final desired = <String, dynamic>{
      for (final requirement in requirements)
        requirement.name: requirement.pubspecValue,
    };
    final addPlan = planner.planAddDependencies(lines, desired);
    final byName = {for (final r in requirements) r.name: r};
    final missing = [
      for (final name in addPlan.added.keys.toList()..sort()) byName[name]!,
    ];
    return PubspecPackagePlan(
      missing: missing,
      present: addPlan.kept.keys.toList()..sort(),
      conflicts: addPlan.conflicts,
      updatedLines: addPlan.conflicts.isEmpty ? addPlan.lines : null,
    );
  }

  /// Writes the pubspec delta and runs `pub get` (unless [runPubGet] is false).
  Future<PubspecPackagePlan> apply(
    PubspecPackagePlan plan, {
    bool runPubGet = true,
  }) async {
    if (!plan.hasChanges) {
      return plan;
    }
    await _pubspec.writeAsString(plan.updatedLines!.join('\n'));
    logger?.success(
      'Added packages: ${plan.missing.map((p) => p.name).join(', ')}',
    );
    if (runPubGet) {
      await runner.pubGet(projectRoot);
    }
    return plan;
  }
}
