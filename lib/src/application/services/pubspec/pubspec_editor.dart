/// A line-preserving pubspec.yaml editor that maintains comments, blank lines,
/// indentation, and top-level ordering while adding missing entries.
///
/// This editor never loads the entire document into a YAML map and re-encodes
/// it. Instead, it operates on the raw line list, finding section boundaries
/// by indentation and inserting new entries at the end of existing sections.
class PubspecEditor {
  final List<String> _lines;
  final Set<String> _addedDeps = {};
  final Set<String> _addedDevDeps = {};
  final Set<String> _addedAssets = {};
  final Set<String> _addedFontFamilies = {};

  PubspecEditor(String content) : _lines = content.split('\n');

  /// Adds dependencies to the `dependencies:` section.
  /// Keys that already exist in dependencies or dev_dependencies are skipped.
  void addDependencies(Map<String, dynamic> deps) {
    _addMapEntries('dependencies:', deps, _addedDeps, checkDevDeps: true);
  }

  /// Adds dependencies to the `dev_dependencies:` section.
  /// Keys that already exist are skipped.
  void addDevDependencies(Map<String, dynamic> deps) {
    _addMapEntries('dev_dependencies:', deps, _addedDevDeps);
  }

  /// Adds asset paths to the `flutter:` section's `assets:` subsection.
  /// Paths that already exist are skipped.
  void addFlutterAssets(List<String> assets) {
    final normalized = assets.where((a) => a.trim().isNotEmpty).toSet().toList()
      ..sort();
    if (normalized.isEmpty) return;

    final flutterRange = _findTopLevelSection('flutter');
    if (flutterRange == null) {
      _appendFlutterSectionWithAssets(normalized);
      _addedAssets.addAll(normalized);
      return;
    }

    final assetsRange = _findSubSection(flutterRange, 'assets:');
    if (assetsRange == null) {
      _insertAssetsSubSection(flutterRange, normalized);
      _addedAssets.addAll(normalized);
      return;
    }

    final existing = _collectAssetEntries(assetsRange);
    final additions = normalized.where((a) => !existing.contains(a)).toList();
    if (additions.isEmpty) return;

    final indent = _getAssetItemIndent(assetsRange);
    for (final asset in additions) {
      _lines.insert(assetsRange.end, '$indent- $asset');
      _addedAssets.add(asset);
    }
  }

  /// Adds font families to the `flutter:` section's `fonts:` subsection.
  /// Families that already exist are skipped.
  void addFlutterFonts(List<PubspecFontFamily> fonts) {
    if (fonts.isEmpty) return;

    final flutterRange = _findTopLevelSection('flutter');
    if (flutterRange == null) {
      _appendFlutterSectionWithFonts(fonts);
      for (final f in fonts) {
        _addedFontFamilies.add(f.family);
      }
      return;
    }

    final fontsRange = _findSubSection(flutterRange, 'fonts:');
    if (fontsRange == null) {
      _insertFontsSubSection(flutterRange, fonts);
      for (final f in fonts) {
        _addedFontFamilies.add(f.family);
      }
      return;
    }

    final existingFamilies = _collectFontFamilies(fontsRange);
    final additions =
        fonts.where((f) => !existingFamilies.contains(f.family)).toList();
    if (additions.isEmpty) return;

    for (final family in additions) {
      final formatted = _formatFontFamily(family, fontsRange);
      _lines.insertAll(fontsRange.end, formatted);
      _addedFontFamilies.add(family.family);
    }
  }

  /// Returns a delta of entries added since construction.
  /// Use [rollbackDelta] to remove exactly those entries.
  PubspecDelta recordDelta() {
    return PubspecDelta(
      dependencies: _addedDeps.toList()..sort(),
      devDependencies: _addedDevDeps.toList()..sort(),
      flutterAssets: _addedAssets.toList()..sort(),
      flutterFonts: _addedFontFamilies.toList()..sort(),
    );
  }

  /// Removes entries recorded in [delta] from the document.
  void rollbackDelta(PubspecDelta delta) {
    _removeSectionEntries('dependencies:', delta.dependencies);
    _removeSectionEntries('dev_dependencies:', delta.devDependencies);
    _removeFlutterAssets(delta.flutterAssets);
    _removeFlutterFamilies(delta.flutterFonts.toSet());
  }

  @override
  String toString() => _lines.join('\n');

  // ── Private: section finding ──────────────────────────────────────

  _SectionRange? _findTopLevelSection(String sectionKey) {
    final keyWithoutColon = sectionKey.endsWith(':')
        ? sectionKey.substring(0, sectionKey.length - 1)
        : sectionKey;
    for (var i = 0; i < _lines.length; i++) {
      final trimmed = _lines[i].trim();
      final lineKey = trimmed.endsWith(':')
          ? trimmed.substring(0, trimmed.length - 1)
          : trimmed;
      final leading = _leadingSpaces(_lines[i]);
      if (lineKey == keyWithoutColon && leading == 0) {
        final end = _findSectionEnd(i, 0);
        return _SectionRange(i, end);
      }
    }
    return null;
  }

  _SectionRange? _findSubSection(_SectionRange parent, String subKey) {
    final keyWithoutColon =
        subKey.endsWith(':') ? subKey.substring(0, subKey.length - 1) : subKey;
    for (var i = parent.start + 1; i < parent.end; i++) {
      final trimmed = _lines[i].trim();
      final lineKey = trimmed.endsWith(':')
          ? trimmed.substring(0, trimmed.length - 1)
          : trimmed;
      if (lineKey == keyWithoutColon) {
        final subIndent = _leadingSpaces(_lines[i]);
        final end = _findSectionEnd(i, subIndent);
        return _SectionRange(i, end);
      }
    }
    return null;
  }

  int _findSectionEnd(int start, int indent) {
    for (var i = start + 1; i < _lines.length; i++) {
      final line = _lines[i];
      if (line.trim().isEmpty || line.trim().startsWith('#')) continue;
      if (_leadingSpaces(line) <= indent) return i;
    }
    return _lines.length;
  }

  // ── Private: map entry insertion ──────────────────────────────────

  void _addMapEntries(
      String sectionKey, Map<String, dynamic> entries, Set<String> addedTracker,
      {bool checkDevDeps = false}) {
    if (entries.isEmpty) return;

    final section = _findTopLevelSection(sectionKey);
    final existing =
        section != null ? _collectSectionKeys(section) : <String>{};

    Set<String>? devExisting;
    if (checkDevDeps) {
      final devSection = _findTopLevelSection('dev_dependencies:');
      devExisting = devSection != null ? _collectSectionKeys(devSection) : null;
    }

    final additions = <String, dynamic>{};
    entries.forEach((key, value) {
      if (!existing.contains(key) &&
          (devExisting == null || !devExisting.contains(key))) {
        additions[key] = value;
      }
    });
    if (additions.isEmpty) return;

    if (section == null) {
      _appendTopLevelSection(sectionKey, entries);
      addedTracker.addAll(entries.keys);
      return;
    }

    final parentIndent = _leadingSpaces(_lines[section.start]);
    final childIndent = ' ' * (parentIndent + 2);

    final sortedEntries = additions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in sortedEntries) {
      final formatted =
          _formatDependencyLines(entry.key, entry.value, childIndent);
      _lines.insertAll(section.end, formatted);
      addedTracker.add(entry.key);
    }
  }

  Set<String> _collectSectionKeys(_SectionRange section) {
    final keys = <String>{};
    final parentIndent = _leadingSpaces(_lines[section.start]);
    for (var i = section.start + 1; i < section.end; i++) {
      final line = _lines[i];
      if (line.trim().isEmpty || line.trim().startsWith('#')) continue;
      if (_leadingSpaces(line) <= parentIndent) break;
      final match = RegExp(r'^([A-Za-z0-9_\-]+):').firstMatch(line.trim());
      if (match != null) keys.add(match.group(1)!);
    }
    return keys;
  }

  void _removeSectionEntries(String sectionKey, List<String> keys) {
    final target = keys.toSet();
    if (target.isEmpty) return;

    final section = _findTopLevelSection(sectionKey);
    if (section == null) return;

    final parentIndent = _leadingSpaces(_lines[section.start]);
    final toRemove = <int>[];
    var inTargetEntry = false;
    var entryStart = -1;

    for (var i = section.start + 1; i < section.end; i++) {
      final line = _lines[i];
      if (line.trim().isEmpty || line.trim().startsWith('#')) continue;
      final indent = _leadingSpaces(line);
      if (indent <= parentIndent) break;

      if (indent == parentIndent + 2) {
        final match = RegExp(r'^([A-Za-z0-9_\-]+):').firstMatch(line.trim());
        if (match != null) {
          if (inTargetEntry) {
            toRemove.addAll(_entryRange(entryStart, i));
          }
          inTargetEntry = target.contains(match.group(1)!);
          entryStart = i;
        }
      }
    }
    if (inTargetEntry) {
      toRemove.addAll(_entryRange(entryStart, section.end));
    }

    for (var i = toRemove.length - 1; i >= 0; i--) {
      _lines.removeAt(toRemove[i]);
    }
  }

  List<int> _entryRange(int start, int end) {
    final range = <int>[];
    var i = start;
    while (i < end) {
      range.add(i);
      i++;
    }
    return range;
  }

  void _appendTopLevelSection(String sectionKey, Map<String, dynamic> entries) {
    if (_lines.isNotEmpty && _lines.last.isNotEmpty) {
      _lines.add('');
    }
    _lines.add(sectionKey);
    final childIndent = '  ';
    final sortedEntries = entries.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in sortedEntries) {
      _lines
          .addAll(_formatDependencyLines(entry.key, entry.value, childIndent));
    }
  }

  List<String> _formatDependencyLines(
      String key, dynamic value, String indent) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('sdk:')) {
        final sdkValue = trimmed.split(':').skip(1).join(':').trim();
        return ['$indent$key:', '$indent  sdk: $sdkValue'];
      }
      return ['$indent$key: $trimmed'];
    }
    if (value is Map) {
      final lines = <String>['$indent$key:'];
      final childIndent = '$indent  ';
      value.forEach((k, v) {
        if (v is Map) {
          lines.add('$childIndent$k:');
          final grandChildIndent = '$childIndent  ';
          v.forEach((gk, gv) {
            lines.add('$grandChildIndent$gk: $gv');
          });
        } else {
          lines.add('$childIndent$k: $v');
        }
      });
      return lines;
    }
    return ['$indent$key: $value'];
  }

  // ── Private: assets ───────────────────────────────────────────────

  Set<String> _collectAssetEntries(_SectionRange range) {
    final assets = <String>{};
    final itemIndent = _leadingSpaces(_lines[range.start]) + 2;
    for (var i = range.start + 1; i < range.end; i++) {
      final line = _lines[i];
      if (line.trim().isEmpty || line.trim().startsWith('#')) continue;
      if (_leadingSpaces(line) < itemIndent) break;
      final trimmed = line.trim();
      if (trimmed.startsWith('- ')) {
        assets.add(trimmed.substring(2).trim());
      }
    }
    return assets;
  }

  String _getAssetItemIndent(_SectionRange assetsRange) {
    return ' ' * (_leadingSpaces(_lines[assetsRange.start]) + 2);
  }

  void _appendFlutterSectionWithAssets(List<String> assets) {
    if (_lines.isNotEmpty && _lines.last.isNotEmpty) _lines.add('');
    _lines.add('flutter:');
    _lines.add('  assets:');
    for (final asset in assets) {
      _lines.add('    - $asset');
    }
  }

  void _insertAssetsSubSection(
      _SectionRange flutterRange, List<String> assets) {
    final flutterIndent = _leadingSpaces(_lines[flutterRange.start]);
    final assetsIndent = ' ' * (flutterIndent + 2);
    final itemIndent = ' ' * (flutterIndent + 4);
    final insertAt = flutterRange.end;
    final insertion = <String>['$assetsIndent' 'assets:'];
    for (final asset in assets) {
      insertion.add('$itemIndent- $asset');
    }
    _lines.insertAll(insertAt, insertion);
  }

  void _removeFlutterAssets(List<String> assets) {
    final target = assets.toSet();
    if (target.isEmpty) return;

    final flutterRange = _findTopLevelSection('flutter');
    if (flutterRange == null) return;
    final assetsRange = _findSubSection(flutterRange, 'assets:');
    if (assetsRange == null) return;

    final itemIndent = _leadingSpaces(_lines[assetsRange.start]) + 2;
    final toRemove = <int>[];
    for (var i = assetsRange.start + 1; i < assetsRange.end; i++) {
      final line = _lines[i];
      if (line.trim().isEmpty || line.trim().startsWith('#')) continue;
      if (_leadingSpaces(line) < itemIndent) break;
      final trimmed = line.trim();
      if (trimmed.startsWith('- ') &&
          target.contains(trimmed.substring(2).trim())) {
        toRemove.add(i);
      }
    }
    for (var i = toRemove.length - 1; i >= 0; i--) {
      _lines.removeAt(toRemove[i]);
    }
  }

  // ── Private: fonts ────────────────────────────────────────────────

  Set<String> _collectFontFamilies(_SectionRange fontsRange) {
    final families = <String>{};
    final itemIndent = _leadingSpaces(_lines[fontsRange.start]) + 2;
    for (var i = fontsRange.start + 1; i < fontsRange.end; i++) {
      final line = _lines[i];
      if (line.trim().isEmpty || line.trim().startsWith('#')) continue;
      if (_leadingSpaces(line) < itemIndent) break;
      final trimmed = line.trim();
      if (trimmed.startsWith('- family:')) {
        final family = trimmed.split(':').skip(1).join(':').trim();
        if (family.isNotEmpty) families.add(family);
      }
    }
    return families;
  }

  List<String> _formatFontFamily(
      PubspecFontFamily family, _SectionRange fontsRange) {
    final fontsIndent = _leadingSpaces(_lines[fontsRange.start]);
    final itemIndent = ' ' * (fontsIndent + 2);
    final innerIndent = ' ' * (fontsIndent + 4);
    final assetIndent = ' ' * (fontsIndent + 6);
    final lines = <String>['$itemIndent- family: ${family.family}'];
    lines.add('$innerIndent' 'fonts:');
    for (final font in family.fonts) {
      lines.add('$assetIndent- asset: ${font.asset}');
      if (font.weight != null) {
        lines.add('$assetIndent  weight: ${font.weight}');
      }
      if (font.style != null && font.style!.isNotEmpty) {
        lines.add('$assetIndent  style: ${font.style}');
      }
    }
    return lines;
  }

  void _appendFlutterSectionWithFonts(List<PubspecFontFamily> fonts) {
    if (_lines.isNotEmpty && _lines.last.isNotEmpty) _lines.add('');
    _lines.add('flutter:');
    _lines.add('  fonts:');
    for (final family in fonts) {
      _lines.add('    - family: ${family.family}');
      _lines.add('      fonts:');
      for (final font in family.fonts) {
        _lines.add('        - asset: ${font.asset}');
        if (font.weight != null) {
          _lines.add('          weight: ${font.weight}');
        }
        if (font.style != null && font.style!.isNotEmpty) {
          _lines.add('          style: ${font.style}');
        }
      }
    }
  }

  void _insertFontsSubSection(
      _SectionRange flutterRange, List<PubspecFontFamily> fonts) {
    final flutterIndent = _leadingSpaces(_lines[flutterRange.start]);
    final fontsIndent = ' ' * (flutterIndent + 2);
    final itemIndent = ' ' * (flutterIndent + 4);
    final innerIndent = ' ' * (flutterIndent + 6);
    final assetIndent = ' ' * (flutterIndent + 8);
    final insertAt = flutterRange.end;
    final insertion = <String>['$fontsIndent' 'fonts:'];
    for (final family in fonts) {
      insertion.add('$itemIndent- family: ${family.family}');
      insertion.add('$innerIndent' 'fonts:');
      for (final font in family.fonts) {
        insertion.add('$assetIndent- asset: ${font.asset}');
        if (font.weight != null) {
          insertion.add('$assetIndent  weight: ${font.weight}');
        }
        if (font.style != null && font.style!.isNotEmpty) {
          insertion.add('$assetIndent  style: ${font.style}');
        }
      }
    }
    _lines.insertAll(insertAt, insertion);
  }

  void _removeFlutterFamilies(Set<String> families) {
    if (families.isEmpty) return;

    final flutterRange = _findTopLevelSection('flutter');
    if (flutterRange == null) return;
    final fontsRange = _findSubSection(flutterRange, 'fonts:');
    if (fontsRange == null) return;

    final itemIndent = _leadingSpaces(_lines[fontsRange.start]) + 2;
    final toRemove = <int>[];
    var inTargetFamily = false;
    var entryStart = -1;

    for (var i = fontsRange.start + 1; i < fontsRange.end; i++) {
      final line = _lines[i];
      if (line.trim().isEmpty || line.trim().startsWith('#')) continue;
      final indent = _leadingSpaces(line);
      if (indent < itemIndent) break;

      if (indent == itemIndent) {
        final trimmed = line.trim();
        if (trimmed.startsWith('- family:')) {
          if (inTargetFamily) {
            toRemove.addAll(_entryRange(entryStart, i));
          }
          final family = trimmed.split(':').skip(1).join(':').trim();
          inTargetFamily = families.contains(family);
          entryStart = i;
        }
      }
    }
    if (inTargetFamily) {
      toRemove.addAll(_entryRange(entryStart, fontsRange.end));
    }

    for (var i = toRemove.length - 1; i >= 0; i--) {
      _lines.removeAt(toRemove[i]);
    }
  }
}

// ── Supporting types ──────────────────────────────────────────────────

class PubspecFontAsset {
  final String asset;
  final int? weight;
  final String? style;

  PubspecFontAsset(this.asset, {this.weight, this.style});
}

class PubspecFontFamily {
  final String family;
  final List<PubspecFontAsset> fonts;

  PubspecFontFamily(this.family, this.fonts);
}

class _SectionRange {
  final int start;
  final int end;

  const _SectionRange(this.start, this.end);
}

int _leadingSpaces(String line) {
  var count = 0;
  for (final char in line.split('')) {
    if (char == ' ') {
      count++;
    } else {
      break;
    }
  }
  return count;
}

class PubspecDelta {
  final List<String> dependencies;
  final List<String> devDependencies;
  final List<String> flutterAssets;
  final List<String> flutterFonts;

  const PubspecDelta({
    this.dependencies = const [],
    this.devDependencies = const [],
    this.flutterAssets = const [],
    this.flutterFonts = const [],
  });

  bool get isEmpty =>
      dependencies.isEmpty &&
      devDependencies.isEmpty &&
      flutterAssets.isEmpty &&
      flutterFonts.isEmpty;
}
