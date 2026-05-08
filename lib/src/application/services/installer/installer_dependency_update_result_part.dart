part of 'installer.dart';

class _DependencyUpdateResult {
  final List<String> lines;
  final List<String> added;
  final List<PubspecDependencyConflict> conflicts;

  const _DependencyUpdateResult(
    this.lines,
    this.added, [
    this.conflicts = const [],
  ]);
}
