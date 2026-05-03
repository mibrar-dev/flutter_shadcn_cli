import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry_directory.dart';
import 'package:flutter_shadcn_cli/src/resolver_v1.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

part 'init_action_engine_exception_part.dart';
part 'init_execution_result_part.dart';
part 'init_execution_record_part.dart';
part 'init_pubspec_delta_part.dart';
part 'init_rollback_result_part.dart';
part 'init_font_family_spec_part.dart';
part 'init_font_asset_spec_part.dart';

typedef InitOptionalActionDecider = Future<bool> Function(
  Map<String, dynamic> action,
);
typedef InitActionGroupSelector = Future<List<Map<String, dynamic>>> Function(
  Map<String, dynamic> action,
  List<Map<String, dynamic>> groups,
);

class InitActionEngine {
  final http.Client _client;
  final bool _ownsClient;

  InitActionEngine({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Future<InitExecutionResult> executeRegistryInit({
    required String projectRoot,
    required RegistryDirectoryEntry registry,
    CliLogger? logger,
    InitOptionalActionDecider? optionalActionDecider,
    InitActionGroupSelector? groupSelector,
  }) async {
    final init = registry.init;
    if (init == null || !registry.hasInlineInit) {
      const message = 'No bootstrap actions defined for this registry.';
      logger?.info(message);
      return const InitExecutionResult(
        dirsCreated: 0,
        filesWritten: 0,
        messages: [message],
        record: InitExecutionRecord.empty,
      );
    }

    final actions = init['actions'];
    if (actions is! List) {
      throw InitActionEngineException('registry.init.actions must be a list');
    }

    return executeActions(
      projectRoot: projectRoot,
      baseUrl: registry.baseUrl,
      actions: actions
          .whereType<Map>()
          .map(
            (entry) =>
                entry.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList(),
      logger: logger,
      optionalActionDecider: optionalActionDecider,
      groupSelector: groupSelector,
    );
  }

  Future<InitExecutionResult> executeActions({
    required String projectRoot,
    required String baseUrl,
    required List<Map<String, dynamic>> actions,
    CliLogger? logger,
    InitOptionalActionDecider? optionalActionDecider,
    InitActionGroupSelector? groupSelector,
  }) async {
    if (actions.isEmpty) {
      return const InitExecutionResult(
        dirsCreated: 0,
        filesWritten: 0,
        messages: <String>[],
        record: InitExecutionRecord.empty,
      );
    }

    var dirsCreated = 0;
    var filesWritten = 0;
    final messages = <String>[];
    final createdDirs = <String>{};
    final writtenFiles = <String>{};
    final writtenAssetCandidates = <String>{};
    var pubspecDelta = InitPubspecDelta.empty;

    for (final action in actions) {
      final type = action['type']?.toString();
      if (type == null || type.isEmpty) {
        throw InitActionEngineException('init action missing "type"');
      }

      if (_isOptionalAction(action) && !_hasActionGroups(action)) {
        final approved = optionalActionDecider == null
            ? false
            : await optionalActionDecider(action);
        if (!approved) {
          continue;
        }
      }

      switch (type) {
        case 'ensureDirs':
          final created = await _runEnsureDirs(projectRoot, action);
          dirsCreated += created.length;
          createdDirs.addAll(created);
          break;
        case 'copyFiles':
          final written = await _runCopyFiles(
            projectRoot,
            baseUrl: baseUrl,
            action: action,
            groupSelector: groupSelector,
          );
          if (written.isEmpty && _hasActionGroups(action)) {
            continue;
          }
          filesWritten += written.length;
          writtenFiles.addAll(written);
          writtenAssetCandidates.addAll(
            written.where(_isDerivableFlutterAssetPath),
          );
          break;
        case 'copyDir':
          final written = await _runCopyFiles(
            projectRoot,
            baseUrl: baseUrl,
            action: action,
            groupSelector: groupSelector,
          );
          if (written.isEmpty && _hasActionGroups(action)) {
            continue;
          }
          filesWritten += written.length;
          writtenFiles.addAll(written);
          writtenAssetCandidates.addAll(
            written.where(_isDerivableFlutterAssetPath),
          );
          break;
        case 'mergePubspec':
          final delta = await _runMergePubspec(
            projectRoot,
            action,
            derivedFlutterAssets: writtenAssetCandidates,
          );
          pubspecDelta = pubspecDelta.merge(delta);
          break;
        case 'message':
          final lines = _runMessage(action);
          messages.addAll(lines);
          for (final line in lines) {
            logger?.info(line);
          }
          break;
        default:
          throw InitActionEngineException(
              'Unsupported init action type: $type');
      }
    }

    return InitExecutionResult(
      dirsCreated: dirsCreated,
      filesWritten: filesWritten,
      messages: messages,
      record: InitExecutionRecord(
        dirsCreated: createdDirs.toList()..sort(),
        filesWritten: writtenFiles.toList()..sort(),
        pubspecDelta: pubspecDelta,
      ),
    );
  }

  Future<InitRollbackResult> rollbackRecordedChanges({
    required String projectRoot,
    required InitExecutionRecord record,
    CliLogger? logger,
  }) async {
    var filesRemoved = 0;
    for (final relPath in record.filesWritten) {
      final safe = ResolverV1.normalizeRelativePath(relPath);
      final absPath = ProjectPathGuard.resolveSafeWritePath(
        projectRoot: projectRoot,
        destinationRelativePath: safe,
      );
      final file = File(absPath);
      if (file.existsSync()) {
        file.deleteSync();
        filesRemoved += 1;
      }
    }

    var dirsRemoved = 0;
    final dirs = record.dirsCreated.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final relPath in dirs) {
      final safe = ResolverV1.normalizeRelativePath(relPath);
      final absPath = ProjectPathGuard.resolveSafeWritePath(
        projectRoot: projectRoot,
        destinationRelativePath: safe,
      );
      final dir = Directory(absPath);
      if (dir.existsSync()) {
        final contents = dir.listSync();
        if (contents.isEmpty) {
          dir.deleteSync();
          dirsRemoved += 1;
        }
      }
    }

    if (!record.pubspecDelta.isEmpty) {
      await _rollbackPubspec(projectRoot, record.pubspecDelta);
    }
    logger?.success(
      'Rolled back inline actions ($filesRemoved files, $dirsRemoved dirs).',
    );
    return InitRollbackResult(
      filesRemoved: filesRemoved,
      dirsRemoved: dirsRemoved,
      reverted: record.pubspecDelta,
    );
  }

  Future<List<String>> _runEnsureDirs(
    String projectRoot,
    Map<String, dynamic> action,
  ) async {
    final dirs = (action['dirs'] as List<dynamic>? ?? const []);
    final created = <String>[];
    for (final entry in dirs) {
      final relPath = ResolverV1.normalizeRelativePath(entry.toString());
      final absPath = ProjectPathGuard.resolveSafeWritePath(
        projectRoot: projectRoot,
        destinationRelativePath: relPath,
      );
      final dir = Directory(absPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        created.add(relPath);
      }
    }
    return created;
  }

  Future<List<String>> _runCopyFiles(
    String projectRoot, {
    required String baseUrl,
    required Map<String, dynamic> action,
    InitActionGroupSelector? groupSelector,
  }) async {
    final base = action['base']?.toString();
    final destBase = action['destBase']?.toString();
    final fromRaw = action['from']?.toString();
    final toRaw = action['to']?.toString();
    final overwrite = action['overwrite'] as bool? ?? false;

    if ((base == null) != (destBase == null)) {
      throw InitActionEngineException(
        'copyFiles requires base and destBase together',
      );
    }

    if ((fromRaw == null) != (toRaw == null)) {
      throw InitActionEngineException(
        'copyFiles requires from and to together when using directory mapping',
      );
    }
    final usesDirMapping = fromRaw != null && toRaw != null;
    final from =
        usesDirMapping ? ResolverV1.normalizeRelativePath(fromRaw) : null;
    final to = usesDirMapping ? ResolverV1.normalizeRelativePath(toRaw) : null;

    final hasFiles = action['files'] is List;
    final hasIndex = action['index'] != null;
    final hasGroups = action['groups'] is List;
    if (usesDirMapping) {
      if ((hasFiles ? 1 : 0) + (hasIndex ? 1 : 0) + (hasGroups ? 1 : 0) != 1) {
        throw InitActionEngineException(
          'copyFiles with from/to requires exactly one of files[], index, or groups',
        );
      }
    } else if (!hasFiles && !hasGroups) {
      throw InitActionEngineException('copyFiles requires files[] or groups[]');
    }

    final files = await _resolveCopyFilesEntries(
      action,
      usesDirMapping: usesDirMapping,
      hasFiles: hasFiles,
      hasIndex: hasIndex,
      hasGroups: hasGroups,
      baseUrl: baseUrl,
      groupSelector: groupSelector,
    );

    final written = <String>[];
    for (final fileEntry in files) {
      final filePath = ResolverV1.normalizeRelativePath(fileEntry.toString());
      final destinationRel = usesDirMapping
          ? InitPathMapper.mapCopyDirDestination(
              filePath: filePath,
              from: from!,
              to: to!,
              base: base,
              destBase: destBase,
            )
          : InitPathMapper.mapCopyFileDestination(
              filePath: filePath,
              base: base,
              destBase: destBase,
            );
      final destinationAbs = ProjectPathGuard.resolveSafeWritePath(
        projectRoot: projectRoot,
        destinationRelativePath: destinationRel,
      );
      final destinationFile = File(destinationAbs);
      if (destinationFile.existsSync() && !overwrite) {
        continue;
      }
      if (!destinationFile.parent.existsSync()) {
        destinationFile.parent.createSync(recursive: true);
      }

      final sourceRel = InitPathMapper.mapSourcePath(
        filePath: filePath,
        base: base,
      );
      final bytes = await _readRemoteBytes(
        baseUrl: baseUrl,
        relativePath: sourceRel,
      );
      await destinationFile.writeAsBytes(bytes, flush: true);
      written.add(destinationRel);
    }
    return written;
  }

  Future<InitPubspecDelta> _runMergePubspec(
    String projectRoot,
    Map<String, dynamic> action,
    {
    Set<String> derivedFlutterAssets = const <String>{},
  }) async {
    final file = File(
      ProjectPathGuard.resolveSafeWritePath(
        projectRoot: projectRoot,
        destinationRelativePath: 'pubspec.yaml',
      ),
    );
    if (!file.existsSync()) {
      throw InitActionEngineException('pubspec.yaml not found in project root');
    }

    final dependencies = _stringMap(action['dependencies']);
    final devDependencies = _stringMap(action['devDependencies']);
    final flutterAssets = <String>{
      ..._stringList(action['flutterAssets']),
      if (action['deriveFlutterAssets'] == true) ...derivedFlutterAssets,
    }.toList()
      ..sort();
    final flutterFonts = _fontFamilies(action['flutterFonts']);

    var lines = file.readAsLinesSync();
    final addedDeps =
        _missingTopLevelMapEntries(lines, 'dependencies', dependencies);
    final addedDevDeps =
        _missingTopLevelMapEntries(lines, 'dev_dependencies', devDependencies);
    final addedAssets = _missingFlutterAssets(lines, flutterAssets);
    final addedFonts = _missingFlutterFontFamilies(lines, flutterFonts);

    lines = _mergeMapSection(lines, 'dependencies', dependencies);
    lines = _mergeMapSection(lines, 'dev_dependencies', devDependencies);
    lines = _mergeFlutterAssets(lines, flutterAssets);
    lines = _mergeFlutterFonts(lines, flutterFonts);

    await file.writeAsString('${lines.join('\n')}\n');

    return InitPubspecDelta(
      dependencies: addedDeps,
      devDependencies: addedDevDeps,
      flutterAssets: addedAssets,
      flutterFonts: addedFonts
          .map(
            (family) => {
              'family': family.family,
              'fonts': family.fonts
                  .map(
                    (font) => {
                      'asset': font.asset,
                      if (font.weight != null) 'weight': font.weight,
                      if (font.style != null && font.style!.isNotEmpty)
                        'style': font.style,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
    );
  }

  List<String> _runMessage(Map<String, dynamic> action) {
    final lines = action['lines'];
    if (lines is! List) {
      throw InitActionEngineException('message.lines must be a list');
    }
    return lines.map((e) => e.toString()).toList();
  }

  Future<List<String>> _loadCopyDirIndexFiles({
    required String baseUrl,
    required String indexPath,
  }) async {
    final body = await _readRemoteString(
      baseUrl: baseUrl,
      relativePath: ResolverV1.normalizeRelativePath(indexPath),
    );
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw InitActionEngineException('copyDir index must be a JSON object');
    }
    final files = decoded['files'];
    if (files is! List) {
      throw InitActionEngineException('copyDir index must contain files[]');
    }
    return files.map((e) => e.toString()).toList();
  }

  Future<List<String>> _resolveCopyFilesEntries(
    Map<String, dynamic> action, {
    required bool usesDirMapping,
    required bool hasFiles,
    required bool hasIndex,
    required bool hasGroups,
    required String baseUrl,
    InitActionGroupSelector? groupSelector,
  }) async {
    if (hasGroups) {
      final groups = (action['groups'] as List<dynamic>)
          .whereType<Map>()
          .map(
            (entry) => entry.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
          .toList();
      final selectedGroups = groupSelector == null
          ? groups.where((group) => group['default'] != false).toList()
          : await groupSelector(action, groups);
      final files = <String>{};
      for (final group in selectedGroups) {
        final groupFiles = group['files'];
        if (groupFiles is! List) {
          continue;
        }
        for (final file in groupFiles) {
          final raw = file.toString();
          files.add(
            usesDirMapping ? p.posix.join(action['from'].toString(), raw) : raw,
          );
        }
      }
      return files.toList()..sort();
    }
    if (usesDirMapping) {
      if (hasFiles) {
        return (action['files'] as List<dynamic>)
            .map((e) => e.toString())
            .toList();
      }
      if (hasIndex) {
        return _loadCopyDirIndexFiles(
          baseUrl: baseUrl,
          indexPath: action['index']!.toString(),
        );
      }
    }
    return (action['files'] as List<dynamic>).map((e) => e.toString()).toList();
  }

  bool _isOptionalAction(Map<String, dynamic> action) =>
      action['optional'] == true;

  bool _hasActionGroups(Map<String, dynamic> action) => action['groups'] is List;

  bool _isDerivableFlutterAssetPath(String relativePath) {
    final normalized = ResolverV1.normalizeRelativePath(relativePath);
    if (normalized.startsWith('lib/')) {
      return false;
    }
    final extension = p.extension(normalized).toLowerCase();
    const assetExtensions = {
      '.jpg',
      '.json',
      '.otf',
      '.png',
      '.svg',
      '.ttf',
      '.woff',
      '.woff2',
    };
    return assetExtensions.contains(extension);
  }

  Future<List<int>> _readRemoteBytes({
    required String baseUrl,
    required String relativePath,
  }) async {
    final localBase = baseUrl.trim();
    if (p.isAbsolute(localBase)) {
      final safeRelative = ResolverV1.normalizeRelativePath(relativePath);
      final file = File(p.normalize(p.join(localBase, safeRelative)));
      if (!await file.exists()) {
        throw InitActionEngineException('File not found: ${file.path}');
      }
      return file.readAsBytes();
    }
    final uri = ResolverV1.resolveUrl(baseUrl, relativePath);
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw InitActionEngineException(
        'Failed to fetch ${uri.toString()} (${response.statusCode})',
      );
    }
    return response.bodyBytes;
  }

  Future<String> _readRemoteString({
    required String baseUrl,
    required String relativePath,
  }) async {
    final bytes = await _readRemoteBytes(
      baseUrl: baseUrl,
      relativePath: relativePath,
    );
    return utf8.decode(bytes);
  }

  Map<String, String> _stringMap(dynamic value) {
    if (value is! Map) {
      return const {};
    }
    return value.map((key, val) => MapEntry(key.toString(), val.toString()));
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value.map((e) => e.toString()).toList();
  }

  List<_FontFamilySpec> _fontFamilies(dynamic value) {
    if (value is! List) {
      return const [];
    }
    final specs = <_FontFamilySpec>[];
    for (final item in value) {
      if (item is! Map) {
        continue;
      }
      final family = item['family']?.toString();
      final fonts = item['fonts'];
      if (family == null || family.trim().isEmpty || fonts is! List) {
        continue;
      }
      final entries = <_FontAssetSpec>[];
      for (final font in fonts) {
        if (font is! Map) {
          continue;
        }
        final asset = font['asset']?.toString();
        if (asset == null || asset.trim().isEmpty) {
          continue;
        }
        entries.add(
          _FontAssetSpec(
            asset: asset,
            weight: font['weight'] is int ? font['weight'] as int : null,
            style: font['style']?.toString(),
          ),
        );
      }
      if (entries.isNotEmpty) {
        specs.add(_FontFamilySpec(family: family, fonts: entries));
      }
    }
    return specs;
  }

  Map<String, String> _missingTopLevelMapEntries(
    List<String> lines,
    String section,
    Map<String, String> desired,
  ) {
    if (desired.isEmpty) {
      return const {};
    }
    final sectionIndex = lines.indexWhere((line) => line.trim() == '$section:');
    if (sectionIndex == -1) {
      return Map<String, String>.from(desired);
    }
    final end = _findTopLevelSectionEnd(lines, sectionIndex);
    final existing = <String>{};
    for (var i = sectionIndex + 1; i < end; i++) {
      final match = RegExp(r'^\s{2}([^:#\s]+)\s*:').firstMatch(lines[i]);
      if (match != null) {
        existing.add(match.group(1)!);
      }
    }
    final missing = <String, String>{};
    desired.forEach((key, value) {
      if (!existing.contains(key)) {
        missing[key] = value;
      }
    });
    return missing;
  }

  List<String> _missingFlutterAssets(List<String> lines, List<String> assets) {
    if (assets.isEmpty) {
      return const [];
    }
    final flutterIndex = lines.indexWhere((line) => line.trim() == 'flutter:');
    if (flutterIndex == -1) {
      return assets.toSet().toList()..sort();
    }
    final assetsIndex = _findChildSection(lines, flutterIndex, 'assets');
    if (assetsIndex == -1) {
      return assets.toSet().toList()..sort();
    }
    final end = _findChildSectionEnd(lines, assetsIndex);
    final existing = <String>{};
    for (var i = assetsIndex + 1; i < end; i++) {
      final match = RegExp(r'^\s{4}-\s+(.+)$').firstMatch(lines[i]);
      if (match != null) {
        existing.add(match.group(1)!.trim());
      }
    }
    final normalized = assets.toSet().toList()..sort();
    return normalized.where((asset) => !existing.contains(asset)).toList();
  }

  List<_FontFamilySpec> _missingFlutterFontFamilies(
    List<String> lines,
    List<_FontFamilySpec> fonts,
  ) {
    if (fonts.isEmpty) {
      return const [];
    }
    final flutterIndex = lines.indexWhere((line) => line.trim() == 'flutter:');
    if (flutterIndex == -1) {
      return fonts;
    }
    final fontsIndex = _findChildSection(lines, flutterIndex, 'fonts');
    if (fontsIndex == -1) {
      return fonts;
    }
    final end = _findChildSectionEnd(lines, fontsIndex);
    final existing = <String>{};
    for (var i = fontsIndex + 1; i < end; i++) {
      final match = RegExp(r'^\s{4}-\s+family:\s+(.+)$').firstMatch(lines[i]);
      if (match != null) {
        existing.add(match.group(1)!.trim());
      }
    }
    return fonts.where((family) => !existing.contains(family.family)).toList();
  }

  List<String> _mergeMapSection(
    List<String> lines,
    String section,
    Map<String, String> additions,
  ) {
    if (additions.isEmpty) {
      return lines;
    }
    final sectionIndex = lines.indexWhere((line) => line.trim() == '$section:');
    final entries = additions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (sectionIndex == -1) {
      final updated = List<String>.from(lines);
      if (updated.isNotEmpty && updated.last.trim().isNotEmpty) {
        updated.add('');
      }
      updated.add('$section:');
      for (final entry in entries) {
        updated.add('  ${entry.key}: ${entry.value}');
      }
      return updated;
    }

    final end = _findTopLevelSectionEnd(lines, sectionIndex);
    final existing = <String>{};
    for (var i = sectionIndex + 1; i < end; i++) {
      final match = RegExp(r'^\s{2}([^:#\s]+)\s*:').firstMatch(lines[i]);
      if (match != null) {
        existing.add(match.group(1)!);
      }
    }
    final missing =
        entries.where((entry) => !existing.contains(entry.key)).toList();
    if (missing.isEmpty) {
      return lines;
    }
    final updated = List<String>.from(lines);
    updated.insertAll(
      end,
      missing.map((entry) => '  ${entry.key}: ${entry.value}'),
    );
    return updated;
  }

  List<String> _mergeFlutterAssets(List<String> lines, List<String> assets) {
    if (assets.isEmpty) {
      return lines;
    }
    final flutterIndex = _ensureFlutterSection(lines);
    final assetsIndex = _findChildSection(lines, flutterIndex, 'assets');
    final normalized = assets.toSet().toList()..sort();

    if (assetsIndex == -1) {
      final end = _findTopLevelSectionEnd(lines, flutterIndex);
      final updated = List<String>.from(lines);
      final block = <String>['  assets:', ...normalized.map((a) => '    - $a')];
      updated.insertAll(end, block);
      return updated;
    }

    final end = _findTopLevelSectionEnd(lines, flutterIndex);
    final existing = <String>{};
    for (var i = assetsIndex + 1; i < end; i++) {
      final match = RegExp(r'^\s{4}-\s+(.+)$').firstMatch(lines[i]);
      if (match != null) {
        existing.add(match.group(1)!.trim());
      }
      if (lines[i].startsWith('  ') &&
          !lines[i].startsWith('    ') &&
          lines[i].trim().isNotEmpty) {
        break;
      }
    }
    final missing = normalized.where((a) => !existing.contains(a)).toList();
    if (missing.isEmpty) {
      return lines;
    }
    final insertAt = _findChildSectionEnd(lines, assetsIndex);
    final updated = List<String>.from(lines);
    updated.insertAll(insertAt, missing.map((a) => '    - $a'));
    return updated;
  }

  List<String> _mergeFlutterFonts(
    List<String> lines,
    List<_FontFamilySpec> fonts,
  ) {
    if (fonts.isEmpty) {
      return lines;
    }
    final flutterIndex = _ensureFlutterSection(lines);
    final fontsIndex = _findChildSection(lines, flutterIndex, 'fonts');
    if (fontsIndex == -1) {
      final end = _findTopLevelSectionEnd(lines, flutterIndex);
      final updated = List<String>.from(lines);
      final block = <String>['  fonts:'];
      for (final family in fonts) {
        block.addAll(_formatFontFamily(family));
      }
      updated.insertAll(end, block);
      return updated;
    }

    final existingFamilies = <String>{};
    final sectionEnd = _findChildSectionEnd(lines, fontsIndex);
    for (var i = fontsIndex + 1; i < sectionEnd; i++) {
      final match = RegExp(r'^\s{4}-\s+family:\s+(.+)$').firstMatch(lines[i]);
      if (match != null) {
        existingFamilies.add(match.group(1)!.trim());
      }
    }

    final additions = fonts
        .where((family) => !existingFamilies.contains(family.family))
        .toList();
    if (additions.isEmpty) {
      return lines;
    }
    final updated = List<String>.from(lines);
    final addLines = <String>[];
    for (final family in additions) {
      addLines.addAll(_formatFontFamily(family));
    }
    updated.insertAll(sectionEnd, addLines);
    return updated;
  }

  List<String> _formatFontFamily(_FontFamilySpec family) {
    final out = <String>[
      '    - family: ${family.family}',
      '      fonts:',
    ];
    for (final entry in family.fonts) {
      out.add('        - asset: ${entry.asset}');
      if (entry.weight != null) {
        out.add('          weight: ${entry.weight}');
      }
      if (entry.style != null && entry.style!.isNotEmpty) {
        out.add('          style: ${entry.style}');
      }
    }
    return out;
  }

  int _ensureFlutterSection(List<String> lines) {
    final index = lines.indexWhere((line) => line.trim() == 'flutter:');
    if (index != -1) {
      return index;
    }
    lines.add('');
    lines.add('flutter:');
    return lines.length - 1;
  }

  int _findTopLevelSectionEnd(List<String> lines, int sectionIndex) {
    for (var i = sectionIndex + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty || line.trim().startsWith('#')) {
        continue;
      }
      if (!line.startsWith(' ')) {
        return i;
      }
    }
    return lines.length;
  }

  int _findChildSection(List<String> lines, int parentIndex, String childName) {
    final end = _findTopLevelSectionEnd(lines, parentIndex);
    final expected = '  $childName:';
    for (var i = parentIndex + 1; i < end; i++) {
      if (lines[i].trimRight() == expected) {
        return i;
      }
    }
    return -1;
  }

  int _findChildSectionEnd(List<String> lines, int childIndex) {
    for (var i = childIndex + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty || line.trim().startsWith('#')) {
        continue;
      }
      if (line.startsWith('  ') && !line.startsWith('    ')) {
        return i;
      }
      if (!line.startsWith(' ')) {
        return i;
      }
    }
    return lines.length;
  }

  Future<void> _rollbackPubspec(
    String projectRoot,
    InitPubspecDelta delta,
  ) async {
    final file = File(
      ProjectPathGuard.resolveSafeWritePath(
        projectRoot: projectRoot,
        destinationRelativePath: 'pubspec.yaml',
      ),
    );
    if (!file.existsSync()) {
      return;
    }
    var lines = file.readAsLinesSync();
    lines = _removeMapEntries(lines, 'dependencies', delta.dependencies.keys);
    lines = _removeMapEntries(
        lines, 'dev_dependencies', delta.devDependencies.keys);
    lines = _removeFlutterAssets(lines, delta.flutterAssets);
    final families = delta.flutterFonts
        .map((entry) => entry['family']?.toString())
        .whereType<String>()
        .where((family) => family.trim().isNotEmpty)
        .toSet();
    lines = _removeFlutterFamilies(lines, families);
    await file.writeAsString('${lines.join('\n')}\n');
  }

  List<String> _removeMapEntries(
    List<String> lines,
    String section,
    Iterable<String> keys,
  ) {
    final target = keys.toSet();
    if (target.isEmpty) {
      return lines;
    }
    final sectionIndex = lines.indexWhere((line) => line.trim() == '$section:');
    if (sectionIndex == -1) {
      return lines;
    }
    final end = _findTopLevelSectionEnd(lines, sectionIndex);
    final updated = List<String>.from(lines);
    for (var i = end - 1; i > sectionIndex; i--) {
      final match = RegExp(r'^\s{2}([^:#\s]+)\s*:').firstMatch(updated[i]);
      if (match != null && target.contains(match.group(1))) {
        updated.removeAt(i);
      }
    }
    final hasEntries = updated
        .sublist(
            sectionIndex + 1, _findTopLevelSectionEnd(updated, sectionIndex))
        .any((line) => line.startsWith('  ') && line.trim().isNotEmpty);
    if (!hasEntries) {
      updated.removeAt(sectionIndex);
    }
    return updated;
  }

  List<String> _removeFlutterAssets(
      List<String> lines, Iterable<String> assets) {
    final target = assets.toSet();
    if (target.isEmpty) {
      return lines;
    }
    final flutterIndex = lines.indexWhere((line) => line.trim() == 'flutter:');
    if (flutterIndex == -1) {
      return lines;
    }
    final assetsIndex = _findChildSection(lines, flutterIndex, 'assets');
    if (assetsIndex == -1) {
      return lines;
    }
    final end = _findChildSectionEnd(lines, assetsIndex);
    final updated = List<String>.from(lines);
    for (var i = end - 1; i > assetsIndex; i--) {
      final match = RegExp(r'^\s{4}-\s+(.+)$').firstMatch(updated[i]);
      if (match != null && target.contains(match.group(1)!.trim())) {
        updated.removeAt(i);
      }
    }
    final hasAssets = updated
        .sublist(
          assetsIndex + 1,
          _findChildSectionEnd(updated, assetsIndex),
        )
        .any((line) => line.startsWith('    - '));
    if (!hasAssets) {
      updated.removeAt(assetsIndex);
    }
    return updated;
  }

  List<String> _removeFlutterFamilies(
    List<String> lines,
    Set<String> families,
  ) {
    if (families.isEmpty) {
      return lines;
    }
    final flutterIndex = lines.indexWhere((line) => line.trim() == 'flutter:');
    if (flutterIndex == -1) {
      return lines;
    }
    final fontsIndex = _findChildSection(lines, flutterIndex, 'fonts');
    if (fontsIndex == -1) {
      return lines;
    }
    final updated = List<String>.from(lines);
    var sectionEnd = _findChildSectionEnd(updated, fontsIndex);
    var i = fontsIndex + 1;
    while (i < sectionEnd) {
      final familyMatch =
          RegExp(r'^\s{4}-\s+family:\s+(.+)$').firstMatch(updated[i]);
      if (familyMatch == null) {
        i += 1;
        continue;
      }
      final family = familyMatch.group(1)!.trim();
      var blockEnd = i + 1;
      while (blockEnd < sectionEnd) {
        final isNextFamily =
            RegExp(r'^\s{4}-\s+family:\s+(.+)$').hasMatch(updated[blockEnd]);
        if (isNextFamily) {
          break;
        }
        blockEnd += 1;
      }
      if (families.contains(family)) {
        updated.removeRange(i, blockEnd);
        sectionEnd -= (blockEnd - i);
        continue;
      }
      i = blockEnd;
    }
    final hasFamilies = updated
        .sublist(fontsIndex + 1, _findChildSectionEnd(updated, fontsIndex))
        .any((line) => RegExp(r'^\s{4}-\s+family:\s+').hasMatch(line));
    if (!hasFamilies) {
      updated.removeAt(fontsIndex);
    }
    return updated;
  }
}
