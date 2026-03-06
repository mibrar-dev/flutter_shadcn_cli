import 'package:args/args.dart';

ArgParser buildCliParser() {
  return ArgParser()
    ..addFlag('verbose', abbr: 'v', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addFlag('wip', negatable: false, help: 'Enable WIP features')
    ..addFlag('experimental',
        negatable: false, help: 'Enable experimental features')
    ..addFlag('offline',
        negatable: false,
        help: 'Disable network calls and use cached registry data only')
    ..addFlag('dev',
        negatable: false, help: 'Persist local registry for dev mode')
    ..addOption('dev-path', help: 'Local registry path to persist for dev mode')
    ..addOption('registry',
        allowed: ['auto', 'local', 'remote'], defaultsTo: 'auto')
    ..addOption(
      'registry-name',
      help: 'Registry namespace selection (e.g. shadcn, orient)',
    )
    ..addOption('registry-path', help: 'Path to local registry folder')
    ..addOption('registry-url', help: 'Remote registry base URL (repo root)')
    ..addFlag(
      'skip-integrity',
      negatable: false,
      help: 'Skip registry SHA-256 integrity verification (development only)',
    )
    ..addOption(
      'registries-url',
      help: 'Remote registries.json directory URL for multi-registry mode',
    )
    ..addOption(
      'registries-path',
      help: 'Local registries.json file or directory path (dev mode)',
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
        ..addOption('apply-file', help: 'Apply theme from local JSON file')
        ..addOption('apply-url', help: 'Apply theme from JSON URL')
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
              help: 'Apply widget theme from a local JSON file',
            )
            ..addOption(
              'apply-url',
              help: 'Apply widget theme from a JSON URL',
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
            help: 'Regenerate /doc/site documentation')
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
  final normalized = List<String>.from(args);
  if (normalized.length >= 3 &&
      normalized.first == 'theme' &&
      normalized[1].startsWith('@') &&
      !normalized[1].contains('/') &&
      normalized[2] == 'widget') {
    final namespaceToken = normalized.removeAt(1);
    normalized.insert(2, namespaceToken);
  }
  final aliasMap = <String, String>{
    'ls': 'list',
    'rm': 'remove',
    'i': 'info',
  };
  final mapped = aliasMap[normalized.first];
  if (mapped == null) {
    return normalized;
  }
  return [mapped, ...normalized.skip(1)];
}
