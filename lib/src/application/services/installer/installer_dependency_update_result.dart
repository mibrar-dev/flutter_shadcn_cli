import 'package:flutter_shadcn_cli/src/application/services/pubspec/pubspec_change_planner.dart';

class InstallerDependencyUpdateResult {
  final List<String> lines;
  final List<String> added;
  final List<PubspecDependencyConflict> conflicts;

  const InstallerDependencyUpdateResult(
    this.lines,
    this.added, [
    this.conflicts = const [],
  ]);
}
