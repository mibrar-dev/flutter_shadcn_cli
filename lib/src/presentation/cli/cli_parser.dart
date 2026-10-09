import 'package:args/args.dart';

/// Builds the v2 CLI parser (P5_CLI_PLAN.md §2).
///
/// Retired with the v1 manifest: `assets`, `locale`, `platform`, `deps`.
/// New: `update`. `--registry <path|url>` replaces `--registry-path` /
/// `--registry-url` / `--registries-path`.
ArgParser buildCliParser() {
  return ArgParser()
    ..addFlag(
      'advanced',
      negatable: false,
      help: 'Show and enable developer and experimental features',
    )
    ..addFlag('verbose', abbr: 'v', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addFlag('version', negatable: false, help: 'Show the CLI version')
    ..addFlag('wip', negatable: false, hide: true)
    ..addFlag('experimental', negatable: false, hide: true)
    ..addFlag(
      'offline',
      negatable: false,
      help: 'Use the cached registry only; never touch the network',
    )
    ..addOption(
      'registry-name',
      help: 'Registry namespace selection (e.g. shadcn)',
    )
    ..addOption(
      'registry',
      help: 'Registry source override: a local path or an http(s) URL',
    )
    ..addCommand(
      'init',
      ArgParser()
        ..addFlag('yes',
            abbr: 'y',
            negatable: false,
            help: 'Run non-interactively and use the default preset')
        ..addOption('dir', help: 'Install root (default: lib/ui/shadcn)')
        ..addOption('theme', help: 'Theme preset id (default: vercel)')
        ..addFlag('json', negatable: false, help: 'Machine-readable output')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'add',
      ArgParser()
        ..addFlag('all',
            abbr: 'a',
            negatable: false,
            help: 'Install every available component')
        ..addFlag('dry-run',
            negatable: false, help: 'Print the plan without writing anything')
        ..addFlag('force',
            abbr: 'f',
            negatable: false,
            help: 'Overwrite locally modified registry files')
        ..addFlag('include-preview',
            negatable: false, help: 'Also copy each component preview.dart')
        ..addFlag('json', negatable: false, help: 'Machine-readable output')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'dry-run',
      ArgParser()
        ..addFlag('all', abbr: 'a', negatable: false)
        ..addFlag('json', negatable: false, help: 'Machine-readable output')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'remove',
      ArgParser()
        ..addFlag('all', abbr: 'a', negatable: false)
        ..addFlag('force', abbr: 'f', negatable: false)
        ..addFlag('purge-user-themes',
            negatable: false, help: 'Also delete <name>_theme.dart user files')
        ..addFlag('json', negatable: false, help: 'Machine-readable output')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'update',
      ArgParser()
        ..addFlag('all', abbr: 'a', negatable: false)
        ..addFlag('check',
            negatable: false,
            help: 'Report only; exit 1 when behind or modified')
        ..addFlag('json', negatable: false, help: 'Machine-readable output')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'list',
      ArgParser()
        ..addFlag('json', negatable: false, help: 'Machine-readable output')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'search',
      ArgParser()
        ..addFlag('json', negatable: false, help: 'Machine-readable output')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'info',
      ArgParser()
        ..addFlag('json', negatable: false, help: 'Machine-readable output')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'theme',
      ArgParser()
        ..addFlag('list', negatable: false)
        ..addFlag('refresh', negatable: false, help: 'Refresh a drifted theme')
        ..addOption('apply', abbr: 'a')
        ..addFlag('json', negatable: false, help: 'Machine-readable output')
        ..addCommand(
          'list',
          ArgParser()
            ..addFlag('json', negatable: false)
            ..addFlag('help', abbr: 'h', negatable: false),
        )
        ..addCommand(
          'apply',
          ArgParser()
            ..addFlag('refresh', negatable: false)
            ..addFlag('json', negatable: false)
            ..addFlag('help', abbr: 'h', negatable: false),
        )
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'doctor',
      ArgParser()
        ..addFlag('json', negatable: false, help: 'Machine-readable output')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'validate',
      ArgParser()
        ..addFlag('json', negatable: false, help: 'Machine-readable output')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'audit',
      ArgParser()
        ..addFlag('json', negatable: false, help: 'Machine-readable output')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'registries',
      ArgParser()
        ..addFlag('json', negatable: false, help: 'Machine-readable output')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'default',
      ArgParser()
        ..addFlag('local',
            negatable: false, help: 'Persist a local development registry')
        ..addFlag('remote',
            negatable: false,
            help: 'Switch back to the published remote registry')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'sync',
      ArgParser()..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'reset',
      ArgParser()..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'project',
      ArgParser()
        ..addCommand(
          'reset',
          ArgParser()
            ..addFlag('undo', negatable: false)
            ..addFlag('help', abbr: 'h', negatable: false),
        )
        ..addCommand(
          'refresh',
          ArgParser()..addFlag('help', abbr: 'h', negatable: false),
        )
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'version',
      ArgParser()
        ..addFlag('check', negatable: false, help: 'Check for updates')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'upgrade',
      ArgParser()
        ..addFlag('force', abbr: 'f', negatable: false)
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'feedback',
      ArgParser()
        ..addFlag('help', abbr: 'h', negatable: false)
        ..addOption('type', abbr: 't')
        ..addOption('title')
        ..addOption('body'),
    )
    ..addCommand(
      'docs',
      ArgParser()
        ..addFlag('generate', abbr: 'g', negatable: false)
        ..addFlag('help', abbr: 'h', negatable: false),
    );
}

List<String> normalizeCliArgs(List<String> args) {
  if (args.isEmpty) {
    return args;
  }
  var normalized = _hoistGlobalAdvancedFlag(List<String>.from(args));
  normalized = _hoistGlobalJsonFlag(normalized);
  normalized = _normalizeCommandAlias(normalized);
  return normalized;
}

List<String> _hoistGlobalAdvancedFlag(List<String> args) {
  final normalized = <String>[];
  var sawAdvanced = false;
  for (final token in args) {
    if (token == '--advanced') {
      sawAdvanced = true;
      continue;
    }
    normalized.add(token);
  }
  return sawAdvanced ? ['--advanced', ...normalized] : normalized;
}

List<String> _hoistGlobalJsonFlag(List<String> args) {
  final commandIndex = _findCommandIndex(args);
  if (commandIndex == null ||
      !_jsonEnabledCommands.contains(args[commandIndex])) {
    return args;
  }
  final command = args[commandIndex];
  final leading = <String>[];
  final trailing = <String>[];
  var sawJson = false;
  for (var i = 0; i < args.length; i++) {
    if (i == commandIndex) {
      continue;
    }
    if (args[i] == '--json') {
      sawJson = true;
      continue;
    }
    if (i < commandIndex) {
      leading.add(args[i]);
    } else {
      trailing.add(args[i]);
    }
  }
  if (!sawJson) {
    return args;
  }
  return [...leading, command, '--json', ...trailing];
}

List<String> _normalizeCommandAlias(List<String> args) {
  final commandIndex = _findCommandIndex(args);
  if (commandIndex == null) {
    return args;
  }
  final aliasMap = <String, String>{'ls': 'list', 'rm': 'remove', 'i': 'info'};
  final mapped = aliasMap[args[commandIndex]];
  if (mapped == null) {
    return args;
  }
  final normalized = List<String>.from(args);
  normalized[commandIndex] = mapped;
  return normalized;
}

int? _findCommandIndex(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final token = args[i];
    if (token == '--') {
      return i + 1 < args.length ? i + 1 : null;
    }
    if (token.startsWith('-')) {
      if (_rootValueOptions.contains(token) && i + 1 < args.length) {
        i++;
      }
      continue;
    }
    return i;
  }
  return null;
}

const _rootValueOptions = <String>{
  '--registry-name',
  '--registry',
};

const _jsonEnabledCommands = <String>{
  'init',
  'add',
  'dry-run',
  'remove',
  'update',
  'doctor',
  'validate',
  'audit',
  'registries',
  'list',
  'search',
  'info',
  'theme',
};
