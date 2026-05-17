import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/pubspec/pubspec_change_planner.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry_directory.dart';
import 'package:flutter_shadcn_cli/src/resolver_v1.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'init_destination_policy.dart';

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
      try {
        InitDestinationPolicy.assertCopyDestination(relPath);
      } catch (e) {
        throw InitActionEngineException(e.toString());
      }
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
      try {
        InitDestinationPolicy.assertCopyDestination(destinationRel);
      } catch (e) {
        throw InitActionEngineException(e.toString());
      }
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
    Map<String, dynamic> action, {
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

    final dependencies = _pubspecDependencyMap(action['dependencies']);
    final devDependencies = _pubspecDependencyMap(action['devDependencies']);
    final duplicateRequestedDeps =
        dependencies.keys.where(devDependencies.containsKey).toList()..sort();
    if (duplicateRequestedDeps.isNotEmpty) {
      throw InitActionEngineException(
        'pubspec.yaml dependency conflict: ${duplicateRequestedDeps.join(', ')} '
        'requested in both dependencies and dev_dependencies.',
      );
    }
    final flutterAssets = <String>{
      ..._stringList(action['flutterAssets']),
      if (action['deriveFlutterAssets'] == true) ...derivedFlutterAssets,
    }.toList()
      ..sort();
    final flutterFonts = _fontFamilies(action['flutterFonts']);

    final lines = file.readAsLinesSync();
    final planner = const PubspecChangePlanner();
    final dependencyPlan = planner.planAddDependencies(lines, dependencies);
    final devDependencyPlan = planner.planAddDependencies(
      lines,
      devDependencies,
      section: 'dev_dependencies',
    );
    final conflicts = [
      ...dependencyPlan.conflicts,
      ...devDependencyPlan.conflicts,
    ];
    if (conflicts.isNotEmpty) {
      throw InitActionEngineException(_formatPubspecConflicts(conflicts));
    }

    final document = _loadPubspecDocument(file);
    final addedDeps =
        _mergeTopLevelMapEntries(document, 'dependencies', dependencies);
    final addedDevDeps =
        _mergeTopLevelMapEntries(document, 'dev_dependencies', devDependencies);
    final addedAssets =
        _mergeFlutterAssetsIntoDocument(document, flutterAssets);
    final addedFonts = _mergeFlutterFontsIntoDocument(document, flutterFonts);

    await file.writeAsString(_encodeYamlDocument(document));

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

  String _formatPubspecConflicts(List<PubspecDependencyConflict> conflicts) {
    final details = conflicts
        .map(
          (conflict) =>
              '${conflict.package} existing ${conflict.existing}, requested ${conflict.requested}',
        )
        .join('; ');
    return 'pubspec.yaml dependency conflict: $details. '
        'Keep the existing constraint, update it manually, or abort.';
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

  bool _hasActionGroups(Map<String, dynamic> action) =>
      action['groups'] is List;

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

  Map<String, dynamic> _stringMap(dynamic value) {
    if (value is! Map) {
      return const {};
    }
    return value.map((key, val) => MapEntry(key.toString(), val));
  }

  Map<String, dynamic> _pubspecDependencyMap(dynamic value) {
    final raw = _stringMap(value);
    if (raw.isEmpty) {
      return const {};
    }
    return raw.map((key, val) {
      if (val is String) {
        final trimmed = val.trim();
        if (trimmed.startsWith('sdk:')) {
          final sdk = trimmed.split(':').skip(1).join(':').trim();
          if (sdk.isNotEmpty) {
            return MapEntry(key, {'sdk': sdk});
          }
        }
      }
      return MapEntry(key, val);
    });
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
    final document = _loadPubspecDocument(file);
    _removeTopLevelMapEntries(
        document, 'dependencies', delta.dependencies.keys);
    _removeTopLevelMapEntries(
      document,
      'dev_dependencies',
      delta.devDependencies.keys,
    );
    _removeFlutterAssetsFromDocument(document, delta.flutterAssets);
    final families = delta.flutterFonts
        .map((entry) => entry['family']?.toString())
        .whereType<String>()
        .where((family) => family.trim().isNotEmpty)
        .toSet();
    _removeFlutterFamiliesFromDocument(document, families);
    await file.writeAsString(_encodeYamlDocument(document));
  }

  Map<String, dynamic> _loadPubspecDocument(File file) {
    final content = file.readAsStringSync();
    final raw = loadYaml(content);
    if (raw is! YamlMap) {
      throw InitActionEngineException('pubspec.yaml must contain a YAML map');
    }
    return _deepConvertYamlMap(raw);
  }

  Map<String, dynamic> _deepConvertYamlMap(YamlMap map) {
    final converted = <String, dynamic>{};
    map.nodes.forEach((keyNode, valueNode) {
      final key = keyNode.value.toString();
      converted[key] = _deepConvertYamlValue(valueNode.value);
    });
    return converted;
  }

  dynamic _deepConvertYamlValue(dynamic value) {
    if (value is YamlMap) {
      return _deepConvertYamlMap(value);
    }
    if (value is YamlList) {
      return value.nodes
          .map((node) => _deepConvertYamlValue(node.value))
          .toList(growable: true);
    }
    return value;
  }

  Map<String, dynamic> _mergeTopLevelMapEntries(
    Map<String, dynamic> document,
    String section,
    Map<String, dynamic> desired,
  ) {
    if (desired.isEmpty) {
      return const {};
    }
    final sectionMap = _ensureTopLevelStringMap(document, section);
    final added = <String, dynamic>{};
    final orderedKeys = desired.keys.toList()..sort();
    for (final key in orderedKeys) {
      if (!sectionMap.containsKey(key)) {
        final value = desired[key]!;
        sectionMap[key] = value;
        added[key] = value;
      }
    }
    return added;
  }

  Map<String, dynamic> _ensureTopLevelStringMap(
    Map<String, dynamic> document,
    String section,
  ) {
    final existing = document[section];
    if (existing == null) {
      final next = <String, dynamic>{};
      document[section] = next;
      return next;
    }
    if (existing is Map<String, dynamic>) {
      return existing;
    }
    if (existing is Map) {
      final next = <String, dynamic>{}
        ..addAll(existing.map((key, value) => MapEntry(key.toString(), value)));
      document[section] = next;
      return next;
    }
    throw InitActionEngineException('pubspec.$section must be a YAML map');
  }

  Map<String, dynamic> _ensureFlutterSectionMap(
    Map<String, dynamic> document,
  ) {
    final existing = document['flutter'];
    if (existing == null) {
      final next = <String, dynamic>{};
      document['flutter'] = next;
      return next;
    }
    if (existing is Map<String, dynamic>) {
      return existing;
    }
    if (existing is Map) {
      final next = <String, dynamic>{}
        ..addAll(existing.map((key, value) => MapEntry(key.toString(), value)));
      document['flutter'] = next;
      return next;
    }
    throw InitActionEngineException('pubspec.flutter must be a YAML map');
  }

  List<String> _mergeFlutterAssetsIntoDocument(
    Map<String, dynamic> document,
    List<String> assets,
  ) {
    if (assets.isEmpty) {
      return const [];
    }
    final flutter = _ensureFlutterSectionMap(document);
    final existingRaw = flutter['assets'];
    final existing = existingRaw is List
        ? existingRaw.map((entry) => entry.toString()).toSet()
        : <String>{};
    final normalized = assets.toSet().toList()..sort();
    final added =
        normalized.where((asset) => !existing.contains(asset)).toList();
    if (added.isEmpty) {
      return const [];
    }
    final merged = <String>{...existing, ...normalized}.toList()..sort();
    flutter['assets'] = merged;
    return added;
  }

  List<_FontFamilySpec> _mergeFlutterFontsIntoDocument(
    Map<String, dynamic> document,
    List<_FontFamilySpec> fonts,
  ) {
    if (fonts.isEmpty) {
      return const [];
    }
    final flutter = _ensureFlutterSectionMap(document);
    final existingRaw = flutter['fonts'];
    final existingFamilies = <String>{};
    final mergedFonts = <Map<String, dynamic>>[];
    if (existingRaw is List) {
      for (final entry in existingRaw) {
        if (entry is Map) {
          final normalized = <String, dynamic>{}..addAll(
              entry.map((key, value) => MapEntry(key.toString(), value)));
          mergedFonts.add(normalized);
          final family = normalized['family']?.toString();
          if (family != null && family.trim().isNotEmpty) {
            existingFamilies.add(family.trim());
          }
        }
      }
    }

    final additions = fonts
        .where((family) => !existingFamilies.contains(family.family))
        .toList();
    if (additions.isEmpty) {
      return const [];
    }
    for (final family in additions) {
      mergedFonts.add(_fontFamilyToMap(family));
    }
    flutter['fonts'] = mergedFonts;
    return additions;
  }

  Map<String, dynamic> _fontFamilyToMap(_FontFamilySpec family) {
    final map = <String, dynamic>{};
    map['family'] = family.family;
    map['fonts'] = family.fonts.map((entry) {
      final font = <String, dynamic>{};
      font['asset'] = entry.asset;
      if (entry.weight != null) {
        font['weight'] = entry.weight;
      }
      if (entry.style != null && entry.style!.isNotEmpty) {
        font['style'] = entry.style;
      }
      return font;
    }).toList(growable: false);
    return map;
  }

  void _removeTopLevelMapEntries(
    Map<String, dynamic> document,
    String section,
    Iterable<String> keys,
  ) {
    final target = keys.toSet();
    if (target.isEmpty) {
      return;
    }
    final existing = document[section];
    if (existing is! Map) {
      return;
    }
    final normalized = <String, dynamic>{}
      ..addAll(existing.map((key, value) => MapEntry(key.toString(), value)));
    normalized.removeWhere((key, _) => target.contains(key));
    if (normalized.isEmpty) {
      document.remove(section);
      return;
    }
    document[section] = normalized;
  }

  void _removeFlutterAssetsFromDocument(
    Map<String, dynamic> document,
    Iterable<String> assets,
  ) {
    final target = assets.toSet();
    if (target.isEmpty) {
      return;
    }
    final flutter = document['flutter'];
    if (flutter is! Map) {
      return;
    }
    final flutterMap = <String, dynamic>{}
      ..addAll(flutter.map((key, value) => MapEntry(key.toString(), value)));
    final existingRaw = flutterMap['assets'];
    if (existingRaw is! List) {
      document['flutter'] = flutterMap;
      return;
    }
    final next = existingRaw
        .map((entry) => entry.toString())
        .where((entry) => !target.contains(entry))
        .toList(growable: false);
    if (next.isEmpty) {
      flutterMap.remove('assets');
    } else {
      flutterMap['assets'] = next;
    }
    document['flutter'] = flutterMap;
  }

  void _removeFlutterFamiliesFromDocument(
    Map<String, dynamic> document,
    Set<String> families,
  ) {
    if (families.isEmpty) {
      return;
    }
    final flutter = document['flutter'];
    if (flutter is! Map) {
      return;
    }
    final flutterMap = <String, dynamic>{}
      ..addAll(flutter.map((key, value) => MapEntry(key.toString(), value)));
    final existingRaw = flutterMap['fonts'];
    if (existingRaw is! List) {
      document['flutter'] = flutterMap;
      return;
    }
    final next = existingRaw.where((entry) {
      if (entry is! Map) {
        return true;
      }
      final family = entry['family']?.toString().trim();
      return family == null || !families.contains(family);
    }).toList(growable: false);
    if (next.isEmpty) {
      flutterMap.remove('fonts');
    } else {
      flutterMap['fonts'] = next;
    }
    document['flutter'] = flutterMap;
  }

  String _encodeYamlDocument(Map<String, dynamic> document) {
    final lines = <String>[];
    document.forEach((key, value) {
      _writeYamlEntry(lines, 0, key, value);
    });
    return '${lines.join('\n')}\n';
  }

  void _writeYamlEntry(
    List<String> lines,
    int indent,
    String key,
    dynamic value,
  ) {
    final prefix = ' ' * indent;
    if (value is Map) {
      lines.add('$prefix$key:');
      value.forEach((childKey, childValue) {
        _writeYamlEntry(
          lines,
          indent + 2,
          childKey.toString(),
          childValue,
        );
      });
      return;
    }
    if (value is List) {
      if (value.isEmpty) {
        lines.add('$prefix$key: []');
        return;
      }
      lines.add('$prefix$key:');
      for (final item in value) {
        _writeYamlListItem(lines, indent + 2, item);
      }
      return;
    }
    lines.add('$prefix$key: ${_encodeYamlScalar(value)}');
  }

  void _writeYamlListItem(List<String> lines, int indent, dynamic value) {
    final prefix = ' ' * indent;
    if (value is Map) {
      if (value.isEmpty) {
        lines.add('$prefix- {}');
        return;
      }
      final entries = value.entries.toList(growable: false);
      final first = entries.first;
      final firstValue = first.value;
      if (firstValue is Map || firstValue is List) {
        lines.add('$prefix- ${first.key}:');
        _writeYamlNestedValue(lines, indent + 4, firstValue);
      } else {
        lines.add(
          '$prefix- ${first.key}: ${_encodeYamlScalar(firstValue)}',
        );
      }
      for (final entry in entries.skip(1)) {
        _writeYamlEntry(lines, indent + 2, entry.key.toString(), entry.value);
      }
      return;
    }
    if (value is List) {
      if (value.isEmpty) {
        lines.add('$prefix- []');
        return;
      }
      lines.add('$prefix-');
      for (final item in value) {
        _writeYamlListItem(lines, indent + 2, item);
      }
      return;
    }
    lines.add('$prefix- ${_encodeYamlScalar(value)}');
  }

  void _writeYamlNestedValue(List<String> lines, int indent, dynamic value) {
    if (value is Map) {
      value.forEach((childKey, childValue) {
        _writeYamlEntry(lines, indent, childKey.toString(), childValue);
      });
      return;
    }
    if (value is List) {
      for (final item in value) {
        _writeYamlListItem(lines, indent, item);
      }
      return;
    }
    lines.add('${' ' * indent}${_encodeYamlScalar(value)}');
  }

  String _encodeYamlScalar(dynamic value) {
    if (value == null) {
      return 'null';
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    final stringValue = value.toString();
    if (stringValue.isEmpty) {
      return "''";
    }
    final safe = RegExp(r'^[A-Za-z0-9_./@:+<>=^~ -]+$');
    final reserved = <String>{
      'null',
      'Null',
      'NULL',
      'true',
      'false',
      'yes',
      'no',
      'on',
      'off',
    };
    if (safe.hasMatch(stringValue) &&
        !stringValue.startsWith('-') &&
        !stringValue.startsWith('{') &&
        !stringValue.startsWith('[') &&
        !stringValue.contains('<') &&
        !stringValue.contains('>') &&
        !stringValue.contains('#') &&
        !stringValue.contains(': ') &&
        !reserved.contains(stringValue)) {
      return stringValue;
    }
    return "'${stringValue.replaceAll("'", "''")}'";
  }
}
