import 'package:flutter_shadcn_cli/src/index_loader.dart';
import 'package:flutter_shadcn_cli/src/index/index_component.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/json_output.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry/component.dart';
import 'package:flutter_shadcn_cli/src/registry/registry_file.dart';

/// Handles `flutter_shadcn list` command.
///
/// Loads the index and prints all components with id, category, and description.
Future<int> handleListCommand({
  required String registryBaseUrl,
  required String registryId,
  required bool refresh,
  required bool offline,
  required bool jsonOutput,
  required CliLogger logger,
  String indexPath = 'index.json',
  String? indexSchemaPath,
}) async {
  if (!jsonOutput) {
    logger.section('📦 Available Components');
  }

  try {
    final loader = IndexLoader(
      registryId: registryId,
      registryBaseUrl: registryBaseUrl,
      indexPath: indexPath,
      indexSchemaPath: indexSchemaPath,
      refresh: refresh,
      offline: offline,
      logger: logger,
    );

    final index = await loader.load();
    final components = (index['components'] as List?)
            ?.map((c) => IndexComponent.fromJson(c as Map<String, dynamic>))
            .toList() ??
        [];

    if (jsonOutput) {
      final payload = jsonEnvelope(
        command: 'list',
        data: {
          'registry': {
            'id': registryId,
            'baseUrl': registryBaseUrl,
          },
          'count': components.length,
          'components': components.map((c) => c.toJson()).toList(),
        },
        meta: {
          'exitCode': ExitCodes.success,
        },
      );
      printJson(payload);
      return ExitCodes.success;
    }

    if (components.isEmpty) {
      logger.info('No components found.');
      return ExitCodes.success;
    }

    // Group by category
    final byCategory = <String, List<IndexComponent>>{};
    for (final comp in components) {
      byCategory.putIfAbsent(comp.category, () => []).add(comp);
    }

    // Print grouped with beautiful formatting
    final sortedCategories = byCategory.keys.toList()..sort();

    for (final category in sortedCategories) {
      // Category header with emoji
      final categoryEmoji = _getCategoryEmoji(category);
      print('');
      print('$categoryEmoji  \x1B[1m${category.toUpperCase()}\x1B[0m');
      print('─' * 60);

      final categoryComponents = byCategory[category]!;
      for (var i = 0; i < categoryComponents.length; i++) {
        final comp = categoryComponents[i];
        final isLast = i == categoryComponents.length - 1;

        // Component name with box drawing
        final prefix = isLast ? '└─' : '├─';
        print(
            '  $prefix \x1B[36m${comp.id.padRight(20)}\x1B[0m \x1B[1m${comp.name}\x1B[0m');

        // Description with subtle color
        if (comp.description.isNotEmpty) {
          final descPrefix = isLast ? '   ' : '│  ';
          final wrappedDesc = _wrapText(comp.description, 56);
          for (final line in wrappedDesc) {
            print('  $descPrefix \x1B[90m$line\x1B[0m');
          }
        }
      }
    }

    print('');
    print('═' * 60);
    logger.info('${components.length} components total.');
    return ExitCodes.success;
  } catch (e) {
    if (jsonOutput) {
      final code = offline
          ? ExitCodeLabels.offlineUnavailable
          : ExitCodeLabels.networkError;
      final payload = jsonEnvelope(
        command: 'list',
        data: {
          'registry': {
            'id': registryId,
            'baseUrl': registryBaseUrl,
          },
        },
        errors: [
          jsonError(code: code, message: e.toString()),
        ],
        meta: {
          'exitCode':
              offline ? ExitCodes.offlineUnavailable : ExitCodes.networkError,
        },
      );
      printJson(payload);
      return offline ? ExitCodes.offlineUnavailable : ExitCodes.networkError;
    }
    logger.error('Failed to load components: $e');
    logger.info('Tip: Check the configured registry URL and try again.');
    return offline ? ExitCodes.offlineUnavailable : ExitCodes.networkError;
  }
}

/// Handles `flutter_shadcn search <query>` command.
///
/// Loads the index, filters and ranks by relevance, and prints matches.
Future<int> handleSearchCommand({
  required String query,
  required String registryBaseUrl,
  required String registryId,
  required bool refresh,
  required bool offline,
  required bool jsonOutput,
  required CliLogger logger,
  String indexPath = 'index.json',
  String? indexSchemaPath,
}) async {
  if (query.isEmpty) {
    if (jsonOutput) {
      final payload = jsonEnvelope(
        command: 'search',
        data: {
          'registry': {
            'id': registryId,
            'baseUrl': registryBaseUrl,
          },
        },
        errors: [
          jsonError(
            code: ExitCodeLabels.usage,
            message: 'Search query is required.',
          ),
        ],
        meta: {
          'exitCode': ExitCodes.usage,
        },
      );
      printJson(payload);
      return ExitCodes.usage;
    }
    logger.error('Please provide a search query.');
    return ExitCodes.usage;
  }

  if (!jsonOutput) {
    logger.section('🔍 Search Results: "$query"');
  }

  try {
    final loader = IndexLoader(
      registryId: registryId,
      registryBaseUrl: registryBaseUrl,
      indexPath: indexPath,
      indexSchemaPath: indexSchemaPath,
      refresh: refresh,
      offline: offline,
      logger: logger,
    );

    final index = await loader.load();
    var components = (index['components'] as List?)
            ?.map((c) => IndexComponent.fromJson(c as Map<String, dynamic>))
            .toList() ??
        [];

    // Filter by query
    components = components.where((c) => c.matches(query)).toList();

    if (jsonOutput) {
      final results = components
          .map((c) => {
                ...c.toJson(),
                'score': c.relevanceScore(query),
              })
          .toList();
      final payload = jsonEnvelope(
        command: 'search',
        data: {
          'query': query,
          'registry': {
            'id': registryId,
            'baseUrl': registryBaseUrl,
          },
          'count': results.length,
          'results': results,
        },
        meta: {
          'exitCode': ExitCodes.success,
        },
      );
      printJson(payload);
      return ExitCodes.success;
    }

    if (components.isEmpty) {
      logger.info('No matches found for "$query".');
      return ExitCodes.success;
    }

    // Sort by relevance score
    components.sort(
        (a, b) => b.relevanceScore(query).compareTo(a.relevanceScore(query)));

    print('');
    for (var i = 0; i < components.length; i++) {
      final comp = components[i];
      final score = comp.relevanceScore(query);
      final scoreBar =
          '\x1B[32m${'█' * ((score / 10).ceil().clamp(0, 10))}\x1B[0m';
      final isLast = i == components.length - 1;
      final prefix = isLast ? '└─' : '├─';

      print(
          '  $prefix \x1B[36m${comp.id.padRight(20)}\x1B[0m \x1B[1m${comp.name}\x1B[0m');
      if (comp.description.isNotEmpty) {
        final descPrefix = isLast ? '   ' : '│  ';
        print('  $descPrefix \x1B[90m${comp.description}\x1B[0m');
      }
      if (comp.tags.isNotEmpty) {
        final tagsPrefix = isLast ? '   ' : '│  ';
        print('  $tagsPrefix \x1B[35m🏷️  ${comp.tags.join(", ")}\x1B[0m');
      }
      final scorePrefix = isLast ? '   ' : '│  ';
      print('  $scorePrefix $scoreBar \x1B[90m($score pts)\x1B[0m');

      if (!isLast) print('  │');
    }

    print('');
    print('═' * 60);
    logger.info('Found ${components.length} matching components.');
    return ExitCodes.success;
  } catch (e) {
    if (jsonOutput) {
      final code = offline
          ? ExitCodeLabels.offlineUnavailable
          : ExitCodeLabels.networkError;
      final payload = jsonEnvelope(
        command: 'search',
        data: {
          'query': query,
          'registry': {
            'id': registryId,
            'baseUrl': registryBaseUrl,
          },
        },
        errors: [
          jsonError(code: code, message: e.toString()),
        ],
        meta: {
          'exitCode':
              offline ? ExitCodes.offlineUnavailable : ExitCodes.networkError,
        },
      );
      printJson(payload);
      return offline ? ExitCodes.offlineUnavailable : ExitCodes.networkError;
    }
    logger.error('Failed to search components: $e');
    logger.info('Tip: Check the configured registry URL and try again.');
    return offline ? ExitCodes.offlineUnavailable : ExitCodes.networkError;
  }
}

/// Handles `flutter_shadcn info <id>` command.
///
/// Loads the index, finds the component, and displays full details.
Future<int> handleInfoCommand({
  required String componentId,
  required String registryBaseUrl,
  required String registryId,
  required bool refresh,
  required bool offline,
  required bool jsonOutput,
  required CliLogger logger,
  String indexPath = 'index.json',
  String? indexSchemaPath,
  Component? registryComponent,
}) async {
  if (componentId.isEmpty) {
    if (jsonOutput) {
      final payload = jsonEnvelope(
        command: 'info',
        data: {
          'registry': {
            'id': registryId,
            'baseUrl': registryBaseUrl,
          },
        },
        errors: [
          jsonError(
            code: ExitCodeLabels.usage,
            message: 'Component id is required.',
          ),
        ],
        meta: {
          'exitCode': ExitCodes.usage,
        },
      );
      printJson(payload);
      return ExitCodes.usage;
    }
    logger.error('Please provide a component id.');
    return ExitCodes.usage;
  }

  try {
    final loader = IndexLoader(
      registryId: registryId,
      registryBaseUrl: registryBaseUrl,
      indexPath: indexPath,
      indexSchemaPath: indexSchemaPath,
      refresh: refresh,
      offline: offline,
      logger: logger,
    );

    final index = await loader.load();
    final components = (index['components'] as List?)
            ?.map((c) => IndexComponent.fromJson(c as Map<String, dynamic>))
            .toList() ??
        [];

    final found = components.firstWhere(
      (c) => c.id == componentId,
      orElse: () => throw Exception('Component "$componentId" not found'),
    );

    // Advertise an import path that points at a file which is actually
    // installed: prefer the real barrel, otherwise the core impl path
    // from the component manifest files list.
    final comp = _withManifestImportPath(found, registryComponent);

    if (jsonOutput) {
      final payload = jsonEnvelope(
        command: 'info',
        data: {
          'registry': {
            'id': registryId,
            'baseUrl': registryBaseUrl,
          },
          'component': comp.toJson(),
        },
        meta: {
          'exitCode': ExitCodes.success,
        },
      );
      printJson(payload);
      return ExitCodes.success;
    }

    logger.section('📋 Component: ${comp.name}');
    print('');
    print('  \x1B[1mID:\x1B[0m           \x1B[36m${comp.id}\x1B[0m');
    print('  \x1B[1mName:\x1B[0m         ${comp.name}');
    print(
        '  \x1B[1mCategory:\x1B[0m     \x1B[35m${_getCategoryEmoji(comp.category)} ${comp.category}\x1B[0m');
    print('  \x1B[1mDescription:\x1B[0m  \x1B[90m${comp.description}\x1B[0m');
    print('');

    if (comp.tags.isNotEmpty) {
      print('  \x1B[1mTags:\x1B[0m');
      for (final tag in comp.tags) {
        print('    \x1B[35m🏷️  $tag\x1B[0m');
      }
      print('');
    }

    if (comp.install.isNotEmpty) {
      print('  \x1B[1mInstall:\x1B[0m      \x1B[32m${comp.install}\x1B[0m');
    }
    if (comp.import_.isNotEmpty) {
      print('  \x1B[1mImport:\x1B[0m       \x1B[90m${comp.import_}\x1B[0m');
    }
    if (comp.importPath.isNotEmpty) {
      print('  \x1B[1mImport Path:\x1B[0m  \x1B[90m${comp.importPath}\x1B[0m');
    }
    print('');

    if (comp.api.isNotEmpty) {
      print('  \x1B[1mAPI:\x1B[0m');
      final constructors = comp.api['constructors'] as List? ?? [];
      final callbacks = comp.api['callbacks'] as List? ?? [];
      if (constructors.isNotEmpty) {
        print('    \x1B[1mConstructors:\x1B[0m');
        for (final c in constructors) {
          print('      \x1B[33m▸\x1B[0m $c');
        }
      }
      if (callbacks.isNotEmpty) {
        print('    \x1B[1mCallbacks:\x1B[0m');
        for (final cb in callbacks) {
          print('      \x1B[33m▸\x1B[0m $cb');
        }
      }
      print('');
    }

    if (comp.examples.isNotEmpty) {
      print('  \x1B[1mExamples:\x1B[0m');
      for (final entry in comp.examples.entries) {
        final label = entry.key;
        final value = entry.value;
        print('    \x1B[32m●\x1B[0m \x1B[1m$label\x1B[0m');
        if (value is String && value.trim().isNotEmpty) {
          final lines = value.trimRight().split('\n');
          for (final line in lines) {
            print('      \x1B[90m$line\x1B[0m');
          }
        }
      }
      print('');
    }

    if ((comp.dependencies['shared'] as List?)?.isNotEmpty ?? false) {
      print('  \x1B[1mShared Dependencies:\x1B[0m');
      for (final dep in comp.dependencies['shared'] as List) {
        print('    \x1B[34m📦\x1B[0m $dep');
      }
      print('');
    }

    if ((comp.dependencies['pubspec'] as Map?)?.isNotEmpty ?? false) {
      print('  \x1B[1mPackage Dependencies:\x1B[0m');
      for (final dep in (comp.dependencies['pubspec'] as Map).keys) {
        print('    \x1B[34m📦\x1B[0m $dep');
      }
      print('');
    }

    if (comp.related.isNotEmpty) {
      print('  \x1B[1mRelated:\x1B[0m');
      for (final rel in comp.related) {
        print('    \x1B[35m→\x1B[0m $rel');
      }
      print('');
    }
    return ExitCodes.success;
  } catch (e) {
    if (jsonOutput) {
      final code = offline
          ? ExitCodeLabels.offlineUnavailable
          : ExitCodeLabels.networkError;
      final payload = jsonEnvelope(
        command: 'info',
        data: {
          'registry': {
            'id': registryId,
            'baseUrl': registryBaseUrl,
          },
        },
        errors: [
          jsonError(code: code, message: e.toString()),
        ],
        meta: {
          'exitCode':
              offline ? ExitCodes.offlineUnavailable : ExitCodes.networkError,
        },
      );
      printJson(payload);
      return offline ? ExitCodes.offlineUnavailable : ExitCodes.networkError;
    }
    logger.error('Failed to load component info: $e');
    logger.info('Tip: Check the configured registry URL and try again.');
    return offline ? ExitCodes.offlineUnavailable : ExitCodes.networkError;
  }
}

/// Rewrites the advertised `import`/`importPath` to a file that is actually
/// installed, using the component manifest files list.
///
/// When [manifest] is unavailable the index entry is returned unchanged
/// (its paths are still normalized to include `components/` by
/// [IndexComponent.fromJson]). When the conventional `<id>/<id>.dart`
/// barrel exists in the manifest, the entry is also returned unchanged.
/// Otherwise the barrel filename is replaced with the best real file:
/// a `<id>.dart` core impl first, then the first deterministic `.dart`
/// file that is not a preview.
IndexComponent _withManifestImportPath(
  IndexComponent comp,
  Component? manifest,
) {
  if (manifest == null || comp.importPath.isEmpty) {
    return comp;
  }
  final relative = _selectManifestImportRelativePath(
    componentId: comp.id,
    files: manifest.files,
  );
  if (relative == null) {
    return comp;
  }
  final base = comp.importPath;
  final dirEnd = base.lastIndexOf('/');
  final dir = dirEnd == -1 ? '' : base.substring(0, dirEnd + 1);
  final importPath = '$dir$relative';
  if (importPath == base) {
    return comp;
  }
  return comp.copyWith(
    importPath: importPath,
    import_: _replaceImportStatementPath(comp.import_, importPath),
  );
}

/// Picks the manifest-relative file to advertise, or `null` when the
/// conventional barrel `<id>.dart` really exists at the component root
/// (meaning the index path is already correct).
String? _selectManifestImportRelativePath({
  required String componentId,
  required List<RegistryFile> files,
}) {
  final barrelName = '$componentId.dart';
  final relatives = <String>[];
  for (final file in files) {
    final relative = _relativeToComponentRoot(
      componentId: componentId,
      source: file.source,
      destination: file.destination,
    );
    if (relative != null &&
        relative.endsWith('.dart') &&
        !relatives.contains(relative)) {
      relatives.add(relative);
    }
  }
  if (relatives.isEmpty) {
    return null;
  }
  if (relatives.contains(barrelName)) {
    return null;
  }
  final sameName = relatives
      .where((path) => path.split('/').last == barrelName)
      .toList()
    ..sort((a, b) => a.length.compareTo(b.length));
  if (sameName.isNotEmpty) {
    return sameName.first;
  }
  final candidates = relatives
      .where((path) => !path.endsWith('preview.dart'))
      .toList();
  if (candidates.isEmpty) {
    return null;
  }
  candidates.sort((a, b) {
    final aPrivate = a.split('/').last.startsWith('_') ? 1 : 0;
    final bPrivate = b.split('/').last.startsWith('_') ? 1 : 0;
    if (aPrivate != bPrivate) {
      return aPrivate.compareTo(bPrivate);
    }
    return a.compareTo(b);
  });
  return candidates.first;
}

/// Resolves a manifest file entry to its path relative to the component
/// root (e.g. `_impl/core/tab_list.dart`), or `null` when neither the
/// source nor the destination sits under a `<componentId>/` directory.
String? _relativeToComponentRoot({
  required String componentId,
  required String source,
  required String destination,
}) {
  for (final raw in [source, destination]) {
    final normalized = raw.replaceAll('\\', '/');
    final marker = '/$componentId/';
    final index = normalized.lastIndexOf(marker);
    if (index == -1) {
      continue;
    }
    final relative = normalized.substring(index + marker.length).trim();
    if (relative.isEmpty ||
        relative.contains('..') ||
        relative.startsWith('{')) {
      continue;
    }
    return relative;
  }
  return null;
}

/// Rewrites the embedded path of a Dart import statement to [importPath].
/// Statements without a recognizable embedded path are returned unchanged.
String _replaceImportStatementPath(String statement, String importPath) {
  if (statement.isEmpty) {
    return statement;
  }
  final pattern = RegExp(r"^(import\s+'package:[^'/]+/)([^']+)(';\s*)$");
  final match = pattern.firstMatch(statement.trim());
  if (match == null) {
    return statement;
  }
  return '${match.group(1)}$importPath${match.group(3)}';
}

/// Returns an emoji for each category
String _getCategoryEmoji(String category) {  switch (category.toLowerCase()) {
    case 'layout':
      return '📐';
    case 'overlay':
      return '🎭';
    case 'utility':
      return '🔧';
    case 'form':
      return '📝';
    case 'display':
      return '💎';
    case 'navigation':
      return '🧭';
    case 'control':
      return '🎮';
    case 'animation':
      return '✨';
    default:
      return '📦';
  }
}

/// Wraps text to a maximum width
List<String> _wrapText(String text, int maxWidth) {
  final words = text.split(' ');
  final lines = <String>[];
  var currentLine = '';

  for (final word in words) {
    if (currentLine.isEmpty) {
      currentLine = word;
    } else if ((currentLine.length + word.length + 1) <= maxWidth) {
      currentLine += ' $word';
    } else {
      lines.add(currentLine);
      currentLine = word;
    }
  }

  if (currentLine.isNotEmpty) {
    lines.add(currentLine);
  }

  return lines.isEmpty ? [''] : lines;
}
