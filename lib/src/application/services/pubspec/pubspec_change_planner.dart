import 'package:yaml/yaml.dart';

class PubspecDependencyConflict {
  final String package;
  final dynamic existing;
  final dynamic requested;

  const PubspecDependencyConflict({
    required this.package,
    required this.existing,
    required this.requested,
  });
}

class PubspecAddPlan {
  final List<String> lines;
  final Map<String, dynamic> added;
  final Map<String, dynamic> kept;
  final List<PubspecDependencyConflict> conflicts;

  const PubspecAddPlan({
    required this.lines,
    required this.added,
    required this.kept,
    required this.conflicts,
  });
}

class PubspecRemovePlan {
  final List<String> lines;
  final List<String> removed;

  const PubspecRemovePlan({
    required this.lines,
    required this.removed,
  });
}

class PubspecChangePlanner {
  const PubspecChangePlanner();

  PubspecAddPlan planAddDependencies(
    List<String> lines,
    Map<String, dynamic> desired, {
    String section = 'dependencies',
  }) {
    if (desired.isEmpty) {
      return PubspecAddPlan(
        lines: lines,
        added: const {},
        kept: const {},
        conflicts: const [],
      );
    }

    final entries = _dependencyEntries(lines, section);
    final secondarySection =
        section == 'dev_dependencies' ? 'dependencies' : 'dev_dependencies';
    final secondaryEntries = _dependencyEntries(lines, secondarySection);
    final added = <String, dynamic>{};
    final kept = <String, dynamic>{};
    final conflicts = <PubspecDependencyConflict>[];
    for (final key in desired.keys.toList()..sort()) {
      final requested = desired[key];
      final existing = entries[key];
      final secondary = secondaryEntries[key];
      if (existing == null) {
        if (secondary != null) {
          conflicts.add(
            PubspecDependencyConflict(
              package: key,
              existing: secondary.value,
              requested: requested,
            ),
          );
          continue;
        }
        added[key] = requested;
        continue;
      }
      if (_valuesEqual(existing.value, requested)) {
        kept[key] = existing.value;
        continue;
      }
      if (_existingConstraintSatisfiesRequest(existing.value, requested)) {
        kept[key] = existing.value;
        continue;
      }
      conflicts.add(
        PubspecDependencyConflict(
          package: key,
          existing: existing.value,
          requested: requested,
        ),
      );
    }

    if (added.isEmpty || conflicts.isNotEmpty) {
      return PubspecAddPlan(
        lines: lines,
        added: added,
        kept: kept,
        conflicts: conflicts,
      );
    }

    return PubspecAddPlan(
      lines: _insertDependencies(lines, section, added),
      added: added,
      kept: kept,
      conflicts: conflicts,
    );
  }

  PubspecRemovePlan planRemoveDependencies(
    List<String> lines,
    Set<String> packages, {
    String section = 'dependencies',
  }) {
    if (packages.isEmpty) {
      return PubspecRemovePlan(lines: lines, removed: const []);
    }
    final entries = _dependencyEntries(lines, section);
    final ranges = <_DependencyEntry>[];
    for (final package in packages) {
      final entry = entries[package];
      if (entry != null) {
        ranges.add(entry);
      }
    }
    if (ranges.isEmpty) {
      return PubspecRemovePlan(lines: lines, removed: const []);
    }
    ranges.sort((a, b) => b.start.compareTo(a.start));
    final updated = List<String>.from(lines);
    for (final entry in ranges) {
      updated.removeRange(entry.start, entry.end);
    }
    return PubspecRemovePlan(
      lines: updated,
      removed: ranges.map((entry) => entry.package).toList()..sort(),
    );
  }

  Map<String, _DependencyEntry> _dependencyEntries(
    List<String> lines,
    String section,
  ) {
    final range = _sectionRange(lines, section);
    if (range == null) {
      return const {};
    }
    final sectionValues = _sectionValues(lines, section);
    final entries = <String, _DependencyEntry>{};
    var index = range.start + 1;
    while (index < range.end) {
      final line = lines[index];
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        index++;
        continue;
      }
      final indent = _leadingSpaces(line);
      if (indent <= range.indent) {
        break;
      }
      final match = RegExp(r'^([A-Za-z0-9_\-]+):').firstMatch(trimmed);
      if (match == null) {
        index++;
        continue;
      }
      final package = match.group(1)!;
      final inline = trimmed.substring(match.end).trim();
      var end = index + 1;
      while (end < range.end) {
        final next = lines[end];
        final nextTrimmed = next.trim();
        if (nextTrimmed.isEmpty || nextTrimmed.startsWith('#')) {
          if (inline.isEmpty &&
              _hasIndentedContinuation(lines, end + 1, range.end, indent)) {
            end++;
            continue;
          }
          break;
        }
        if (_leadingSpaces(next) <= indent) {
          break;
        }
        end++;
      }
      entries[package] = _DependencyEntry(
        package: package,
        start: index,
        end: end,
        value: sectionValues[package] ??
            (inline.isEmpty
                ? _dependencyBlockValue(lines, index + 1, end, indent)
                : _parseYamlScalar(inline)),
      );
      index = end;
    }
    return entries;
  }

  Map<String, dynamic> _sectionValues(List<String> lines, String section) {
    final dynamic decoded;
    try {
      decoded = loadYaml(lines.join('\n'));
    } catch (_) {
      return const {};
    }
    if (decoded is! YamlMap) {
      return const {};
    }
    final rawSection = decoded[section];
    if (rawSection is! YamlMap) {
      return const {};
    }
    return rawSection.nodes.map(
      (key, value) => MapEntry(
        key.value.toString(),
        _convertYaml(value.value),
      ),
    );
  }

  dynamic _parseYamlScalar(String value) {
    try {
      return _convertYaml(loadYaml(value));
    } catch (_) {
      return value;
    }
  }

  dynamic _dependencyBlockValue(
    List<String> lines,
    int start,
    int end,
    int parentIndent,
  ) {
    final values = <String, dynamic>{};
    for (var i = start; i < end; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      if (_leadingSpaces(line) <= parentIndent) {
        continue;
      }
      final match = RegExp(r'^([^:]+):\s*(.*)$').firstMatch(trimmed);
      if (match == null) {
        continue;
      }
      values[match.group(1)!.trim()] = match.group(2)!.trim();
    }
    return values;
  }

  List<String> _insertDependencies(
    List<String> lines,
    String section,
    Map<String, dynamic> additions,
  ) {
    final updated = List<String>.from(lines);
    final range = _sectionRange(updated, section);
    final entries = additions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (range == null) {
      if (updated.isNotEmpty && updated.last.trim().isNotEmpty) {
        updated.add('');
      }
      updated.add('$section:');
      for (final entry in entries) {
        updated.addAll(_formatDependency(entry.key, entry.value, '  '));
      }
      return updated;
    }
    final insertion = <String>[];
    final childIndent = ' ' * (range.indent + 2);
    for (final entry in entries) {
      insertion.addAll(_formatDependency(entry.key, entry.value, childIndent));
    }
    updated.insertAll(range.end, insertion);
    return updated;
  }

  List<String> _formatDependency(
    String package,
    dynamic value,
    String indent,
  ) {
    if (value is Map) {
      final lines = <String>['$indent$package:'];
      final childIndent = '$indent  ';
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      for (final entry in entries) {
        lines.addAll(
            _formatMapEntry(entry.key.toString(), entry.value, childIndent));
      }
      return lines;
    }
    final text = value.toString();
    if (text.trim().startsWith('sdk:')) {
      final sdkValue = text.split(':').skip(1).join(':').trim();
      return ['$indent$package:', '$indent  sdk: $sdkValue'];
    }
    return ['$indent$package: $text'];
  }

  List<String> _formatMapEntry(String key, dynamic value, String indent) {
    if (value is Map) {
      final lines = <String>['$indent$key:'];
      final childIndent = '$indent  ';
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      for (final entry in entries) {
        lines.addAll(
            _formatMapEntry(entry.key.toString(), entry.value, childIndent));
      }
      return lines;
    }
    return ['$indent$key: $value'];
  }

  _SectionRange? _sectionRange(List<String> lines, String section) {
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim() != '$section:') {
        continue;
      }
      final indent = _leadingSpaces(lines[i]);
      var end = lines.length;
      for (var j = i + 1; j < lines.length; j++) {
        final trimmed = lines[j].trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) {
          continue;
        }
        if (_leadingSpaces(lines[j]) <= indent) {
          end = j;
          break;
        }
      }
      return _SectionRange(i, end, indent);
    }
    return null;
  }

  bool _hasIndentedContinuation(
    List<String> lines,
    int start,
    int end,
    int parentIndent,
  ) {
    for (var i = start; i < end; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      return _leadingSpaces(lines[i]) > parentIndent;
    }
    return false;
  }

  bool _valuesEqual(dynamic existing, dynamic requested) {
    return _canonical(existing).toString() == _canonical(requested).toString();
  }

  bool _existingConstraintSatisfiesRequest(
    dynamic existing,
    dynamic requested,
  ) {
    final existingText = _canonical(existing)?.toString().trim();
    final requestedText = _canonical(requested)?.toString().trim();
    if (existingText == null || requestedText == null) {
      return false;
    }
    if (existingText == 'any' || requestedText == 'any') {
      return true;
    }
    final existingRange = _CaretRange.tryParse(existingText);
    final requestedRange = _CaretRange.tryParse(requestedText);
    if (existingRange == null || requestedRange == null) {
      return false;
    }
    return requestedRange.allows(existingRange.minimum);
  }

  dynamic _canonical(dynamic value) {
    if (value is YamlMap) {
      return _convertYaml(value);
    }
    if (value is Map) {
      return Map.fromEntries(
        value.entries
            .map((entry) =>
                MapEntry(entry.key.toString(), _canonical(entry.value)))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key)),
      );
    }
    if (value is YamlList) {
      return _convertYaml(value);
    }
    if (value is List) {
      return value.map(_canonical).toList();
    }
    final text = value?.toString();
    final sdkMatch =
        text == null ? null : RegExp(r'^sdk:\s*(.+)$').firstMatch(text.trim());
    if (sdkMatch != null) {
      return {'sdk': sdkMatch.group(1)!.trim()};
    }
    return text;
  }

  dynamic _convertYaml(dynamic value) {
    if (value is YamlMap) {
      return Map.fromEntries(
        value.nodes.entries
            .map(
              (entry) => MapEntry(
                entry.key.value.toString(),
                _convertYaml(entry.value.value),
              ),
            )
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key)),
      );
    }
    if (value is YamlList) {
      return value.nodes.map((node) => _convertYaml(node.value)).toList();
    }
    return value;
  }

  int _leadingSpaces(String line) => line.length - line.trimLeft().length;
}

class _DependencyEntry {
  final String package;
  final int start;
  final int end;
  final dynamic value;

  const _DependencyEntry({
    required this.package,
    required this.start,
    required this.end,
    required this.value,
  });
}

class _SectionRange {
  final int start;
  final int end;
  final int indent;

  const _SectionRange(this.start, this.end, this.indent);
}

class _CaretRange {
  final _Semver minimum;
  final _Semver exclusiveMaximum;

  const _CaretRange(this.minimum, this.exclusiveMaximum);

  static _CaretRange? tryParse(String value) {
    final match = RegExp(r'^\^(\d+)\.(\d+)\.(\d+)$').firstMatch(value);
    if (match == null) {
      return null;
    }
    final minimum = _Semver(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    final maximum = minimum.major > 0
        ? _Semver(minimum.major + 1, 0, 0)
        : minimum.minor > 0
            ? _Semver(0, minimum.minor + 1, 0)
            : _Semver(0, 0, minimum.patch + 1);
    return _CaretRange(minimum, maximum);
  }

  bool allows(_Semver version) {
    return version.compareTo(minimum) >= 0 &&
        version.compareTo(exclusiveMaximum) < 0;
  }
}

class _Semver implements Comparable<_Semver> {
  final int major;
  final int minor;
  final int patch;

  const _Semver(this.major, this.minor, this.patch);

  @override
  int compareTo(_Semver other) {
    final majorDiff = major.compareTo(other.major);
    if (majorDiff != 0) {
      return majorDiff;
    }
    final minorDiff = minor.compareTo(other.minor);
    if (minorDiff != 0) {
      return minorDiff;
    }
    return patch.compareTo(other.patch);
  }
}
