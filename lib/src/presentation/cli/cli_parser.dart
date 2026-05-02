import 'package:args/args.dart';

ArgParser buildCliParser() {
  return ArgParser()
    ..addFlag(
      'advanced',
      negatable: false,
      help: 'Show and enable developer and experimental features',
    )
    ..addFlag('verbose', abbr: 'v', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addFlag('wip', negatable: false, hide: true)
    ..addFlag('experimental', negatable: false, hide: true)
    ..addFlag('offline',
        negatable: false,
        help: 'Disable network calls and use cached registry data only')
    ..addOption(
      'registry-name',
      help: 'Registry namespace selection (e.g. shadcn, orient)',
    )
    ..addOption('registry-path', hide: true)
    ..addOption('registry-url', hide: true)
    ..addFlag(
      'skip-integrity',
      negatable: false,
      hide: true,
    )
    ..addOption(
      'registries-path',
      hide: true,
    )
    ..addCommand(
      'init',
      ArgParser()
        ..addFlag(
          'yes',
          abbr: 'y',
          negatable: false,
          help: 'Run non-interactively and use defaults',
        )
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'theme',
      ArgParser()
        ..addFlag('list', negatable: false)
        ..addFlag('refresh', negatable: false, help: 'Refresh cache')
        ..addOption('apply', abbr: 'a')
        ..addOption('apply-file', hide: true)
        ..addOption('apply-url', hide: true)
        ..addCommand(
          'widget',
          ArgParser()
            ..addFlag('list', negatable: false)
            ..addFlag(
              'list-targets',
              negatable: false,
              help: 'List theme targets for the selected component',
            )
            ..addOption(
              'apply-file',
              hide: true,
            )
            ..addOption(
              'apply-url',
              hide: true,
            )
            ..addFlag(
              'reset',
              negatable: false,
              help: 'Reset widget theme overrides for the selected component',
            )
            ..addFlag('help', abbr: 'h', negatable: false),
        )
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'add',
      ArgParser()
        ..addFlag('all', abbr: 'a', negatable: false)
        ..addMultiOption(
          'include-files',
          help:
              'Optional file kinds to include (readme, preview, meta). Comma-separated or repeated.',
        )
        ..addMultiOption(
          'exclude-files',
          help:
              'Optional file kinds to exclude (readme, preview, meta). Comma-separated or repeated.',
        )
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'dry-run',
      ArgParser()
        ..addFlag('all', abbr: 'a', negatable: false)
        ..addFlag('json',
            negatable: false, help: 'Output machine-readable JSON')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'remove',
      ArgParser()
        ..addFlag('all', abbr: 'a', negatable: false)
        ..addFlag('force', abbr: 'f', negatable: false)
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'sync',
      ArgParser()..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'doctor',
      ArgParser()
        ..addFlag('json',
            negatable: false, help: 'Output machine-readable JSON')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'validate',
      ArgParser()
        ..addFlag('json',
            negatable: false, help: 'Output machine-readable JSON')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'audit',
      ArgParser()
        ..addFlag('json',
            negatable: false, help: 'Output machine-readable JSON')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'deps',
      ArgParser()
        ..addFlag('all',
            abbr: 'a',
            negatable: false,
            help: 'Compare dependencies for all registry components')
        ..addFlag('json',
            negatable: false, help: 'Output machine-readable JSON')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'docs',
      ArgParser()
        ..addFlag('generate',
            abbr: 'g',
            negatable: false,
            help: 'Regenerate docs/reference/commands documentation')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'assets',
      ArgParser()
        ..addFlag('icons', negatable: false, help: 'Install icon font assets')
        ..addFlag(
          'typography',
          negatable: false,
          help: 'Install typography font assets (GeistSans/GeistMono)',
        )
        ..addFlag('fonts', negatable: false, help: 'Alias for --typography')
        ..addFlag('list', negatable: false, help: 'List available assets')
        ..addFlag('all', abbr: 'a', negatable: false)
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'platform',
      ArgParser()
        ..addMultiOption(
          'set',
          help: 'Set platform target path (platform.section=path)',
        )
        ..addMultiOption(
          'reset',
          help: 'Remove platform target override (platform.section)',
        )
        ..addFlag('list', negatable: false, help: 'List platform targets')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'registries',
      ArgParser()
        ..addFlag(
          'json',
          negatable: false,
          help: 'Output machine-readable JSON',
        )
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'default',
      ArgParser()..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'list',
      ArgParser()
        ..addFlag('refresh', negatable: false, help: 'Refresh cache')
        ..addFlag('json',
            negatable: false, help: 'Output machine-readable JSON')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'search',
      ArgParser()
        ..addFlag('refresh', negatable: false, help: 'Refresh cache')
        ..addFlag('json',
            negatable: false, help: 'Output machine-readable JSON')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'info',
      ArgParser()
        ..addFlag('refresh', negatable: false, help: 'Refresh cache')
        ..addFlag('json',
            negatable: false, help: 'Output machine-readable JSON')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'install-skill',
      ArgParser()
        ..addOption('skill', abbr: 's', help: 'Skill id to install')
        ..addOption('model', abbr: 'm', help: 'Model name (e.g., gpt-4)')
        ..addOption('skills-url', help: 'Override skills base URL/path')
        ..addFlag('symlink',
            negatable: false, help: 'Symlink shared skill to model')
        ..addFlag('list', negatable: false, help: 'List installed skills')
        ..addFlag('available',
            abbr: 'a',
            negatable: false,
            help: 'List available skills from registry')
        ..addFlag('interactive',
            abbr: 'i',
            negatable: false,
            help: 'Interactive multi-skill installation')
        ..addOption('uninstall',
            help: 'Uninstall skill (specify --model for single removal)')
        ..addFlag('uninstall-interactive',
            negatable: false,
            help: 'Interactive removal (choose skills and models)')
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
        ..addFlag('force',
            abbr: 'f',
            negatable: false,
            help: 'Force upgrade even if already latest')
        ..addFlag('help', abbr: 'h', negatable: false),
    )
    ..addCommand(
      'feedback',
      ArgParser()
        ..addFlag('help', abbr: 'h', negatable: false)
        ..addOption('type',
            abbr: 't',
            help:
                'Feedback type: bug, feature, docs, question, performance, other')
        ..addOption('title', help: 'Issue title')
        ..addOption('body', help: 'Issue description/body'),
    );
}

List<String> normalizeCliArgs(List<String> args) {
  if (args.isEmpty) {
    return args;
  }
  var normalized = _hoistGlobalAdvancedFlag(List<String>.from(args));
  normalized = _hoistGlobalJsonFlag(normalized);
  normalized = _hoistHiddenDeveloperFlags(normalized);
  normalized = _normalizeThemeWidgetNamespace(normalized);
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
  if (commandIndex == null || !_jsonEnabledCommands.contains(args[commandIndex])) {
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

List<String> _normalizeThemeWidgetNamespace(List<String> args) {
  final commandIndex = _findCommandIndex(args);
  if (commandIndex == null) {
    return args;
  }
  final normalized = List<String>.from(args);
  if (normalized.length >= 3 &&
      normalized[commandIndex] == 'theme' &&
      normalized.length > commandIndex + 2 &&
      normalized[commandIndex + 1].startsWith('@') &&
      !normalized[commandIndex + 1].contains('/') &&
      normalized[commandIndex + 2] == 'widget') {
    final namespaceToken = normalized.removeAt(commandIndex + 1);
    normalized.insert(commandIndex + 2, namespaceToken);
  }
  return normalized;
}

List<String> _normalizeCommandAlias(List<String> args) {
  final commandIndex = _findCommandIndex(args);
  if (commandIndex == null) {
    return args;
  }
  final aliasMap = <String, String>{
    'ls': 'list',
    'rm': 'remove',
    'i': 'info',
  };
  final mapped = aliasMap[args[commandIndex]];
  if (mapped == null) {
    return args;
  }
  final normalized = List<String>.from(args);
  normalized[commandIndex] = mapped;
  return normalized;
}

List<String> _hoistHiddenDeveloperFlags(List<String> args) {
  final commandIndex = _findCommandIndex(args);
  if (commandIndex == null) {
    return args;
  }
  final leading = args.sublist(0, commandIndex);
  final hoisted = <String>[];
  final commandAndRest = <String>[];

  var i = commandIndex;
  while (i < args.length) {
    final token = args[i];
    final isAfterCommand = i > commandIndex;
    if (isAfterCommand && _isHiddenDeveloperFlagToken(token)) {
      hoisted.add(token);
      if (_hiddenDeveloperValueOptions.contains(token) && i + 1 < args.length) {
        hoisted.add(args[i + 1]);
        i += 2;
        continue;
      }
      i++;
      continue;
    }
    commandAndRest.add(token);
    i++;
  }

  return [...leading, ...hoisted, ...commandAndRest];
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

bool _isHiddenDeveloperFlagToken(String token) {
  if (_hiddenDeveloperFlagOptions.contains(token) ||
      _hiddenDeveloperValueOptions.contains(token)) {
    return true;
  }
  return _hiddenDeveloperValueOptions
      .any((option) => token.startsWith('$option='));
}

const _hiddenDeveloperValueOptions = <String>{
  '--registries-path',
  '--registry-path',
  '--registry-url',
};

const _hiddenDeveloperFlagOptions = <String>{
  '--skip-integrity',
};

const _rootValueOptions = <String>{
  '--registry-name',
  ..._hiddenDeveloperValueOptions,
};

const _jsonEnabledCommands = <String>{
  'dry-run',
  'doctor',
  'validate',
  'audit',
  'deps',
  'registries',
  'list',
  'search',
  'info',
};
