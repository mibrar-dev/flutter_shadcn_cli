class CliCommandGroupMeta {
  final String title;
  final String slug;
  final int sortOrder;
  final List<CliCommandMeta> commands;

  const CliCommandGroupMeta({
    required this.title,
    required this.slug,
    required this.sortOrder,
    required this.commands,
  });
}

class CliCommandMeta {
  final String id;
  final String description;
  final int sortOrder;
  final bool advanced;
  final List<String> aliases;
  final String usage;
  final List<CliArgumentMeta> arguments;
  final List<CliFlagMeta> flags;
  final List<String> examples;
  final String notes;
  final List<String> seeAlso;

  const CliCommandMeta({
    required this.id,
    required this.description,
    required this.sortOrder,
    required this.usage,
    this.advanced = false,
    this.aliases = const [],
    this.arguments = const [],
    this.flags = const [],
    this.examples = const [],
    this.notes = '',
    this.seeAlso = const [],
  });
}

class CliArgumentMeta {
  final String name;
  final bool required;
  final String description;

  const CliArgumentMeta(this.name, this.required, this.description);
}

class CliFlagMeta {
  final String name;
  final String short;
  final String defaultValue;
  final String description;
  final bool advanced;

  const CliFlagMeta({
    required this.name,
    required this.description,
    this.short = '',
    this.defaultValue = '',
    this.advanced = false,
  });
}

const cliCommandMetadata = <CliCommandGroupMeta>[
  CliCommandGroupMeta(
    title: 'Components',
    slug: 'components',
    sortOrder: 10,
    commands: [
      CliCommandMeta(
        id: 'add',
        description: 'Install one or more components.',
        sortOrder: 10,
        usage: 'flutter_shadcn add <component...> [flags]',
        arguments: [
          CliArgumentMeta(
            '<component...>',
            true,
            'Component names or @namespace/component addresses.',
          ),
        ],
        flags: [
          CliFlagMeta(
            name: '--all',
            short: '-a',
            defaultValue: 'false',
            description: 'Install every available component.',
          ),
          CliFlagMeta(
            name: '--include-files <kind>',
            description:
                'Optional file kinds to include: readme, preview, or meta.',
          ),
          CliFlagMeta(
            name: '--exclude-files <kind>',
            description:
                'Optional file kinds to exclude: readme, preview, or meta.',
          ),
        ],
        examples: [
          'flutter_shadcn add button',
          'flutter_shadcn add @shadcn/button',
        ],
        notes:
            'Use namespaced addresses when multiple registries provide the same component.',
        seeAlso: ['list', 'search', 'info', 'remove'],
      ),
      CliCommandMeta(
        id: 'remove',
        description: 'Remove one or more installed components.',
        sortOrder: 20,
        aliases: ['rm'],
        usage: 'flutter_shadcn remove <component...> [flags]',
        arguments: [
          CliArgumentMeta(
            '<component...>',
            false,
            'Installed component names to remove.',
          ),
        ],
        flags: [
          CliFlagMeta(
            name: '--all',
            short: '-a',
            defaultValue: 'false',
            description: 'Remove all installed components.',
          ),
          CliFlagMeta(
            name: '--force',
            short: '-f',
            defaultValue: 'false',
            description: 'Skip confirmation prompts.',
          ),
        ],
        examples: [
          'flutter_shadcn remove button',
          'flutter_shadcn rm dialog',
        ],
        seeAlso: ['add', 'list'],
      ),
      CliCommandMeta(
        id: 'dry-run',
        description: 'Preview what would be installed.',
        sortOrder: 30,
        usage: 'flutter_shadcn dry-run <component...> [flags]',
        arguments: [
          CliArgumentMeta(
            '<component...>',
            false,
            'Component names or @namespace/component addresses to preview.',
          ),
        ],
        flags: [
          CliFlagMeta(
            name: '--all',
            short: '-a',
            defaultValue: 'false',
            description: 'Preview installing every available component.',
          ),
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: [
          'flutter_shadcn dry-run button',
          'flutter_shadcn dry-run --json @shadcn/card',
        ],
        seeAlso: ['add', 'deps'],
      ),
      CliCommandMeta(
        id: 'list',
        description: 'List available components.',
        sortOrder: 40,
        aliases: ['ls'],
        usage: 'flutter_shadcn list [flags]',
        flags: [
          CliFlagMeta(
            name: '--refresh',
            defaultValue: 'false',
            description: 'Refresh cached registry data before listing.',
          ),
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: [
          'flutter_shadcn list',
          'flutter_shadcn ls --refresh',
        ],
        seeAlso: ['search', 'info', 'add'],
      ),
      CliCommandMeta(
        id: 'search',
        description: 'Search for components.',
        sortOrder: 50,
        usage: 'flutter_shadcn search <query> [flags]',
        arguments: [
          CliArgumentMeta('<query>', false, 'Search text to match.'),
        ],
        flags: [
          CliFlagMeta(
            name: '--refresh',
            defaultValue: 'false',
            description: 'Refresh cached registry data before searching.',
          ),
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: [
          'flutter_shadcn search button',
          'flutter_shadcn search input --json',
        ],
        seeAlso: ['list', 'info'],
      ),
      CliCommandMeta(
        id: 'info',
        description: 'Show component details.',
        sortOrder: 60,
        aliases: ['i'],
        usage: 'flutter_shadcn info <component> [flags]',
        arguments: [
          CliArgumentMeta(
            '<component>',
            true,
            'Component name or @namespace/component address.',
          ),
        ],
        flags: [
          CliFlagMeta(
            name: '--refresh',
            defaultValue: 'false',
            description: 'Refresh cached registry data before loading details.',
          ),
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: [
          'flutter_shadcn info button',
          'flutter_shadcn i @shadcn/dialog',
        ],
        seeAlso: ['list', 'search', 'add'],
      ),
    ],
  ),
  CliCommandGroupMeta(
    title: 'Project',
    slug: 'project',
    sortOrder: 20,
    commands: [
      CliCommandMeta(
        id: 'init',
        description: 'Initialize shadcn_flutter in the current project.',
        sortOrder: 10,
        usage: 'flutter_shadcn init [namespace] [flags]',
        arguments: [
          CliArgumentMeta(
            '[namespace]',
            false,
            'Registry namespace to initialize from.',
          ),
        ],
        flags: [
          CliFlagMeta(
            name: '--yes',
            short: '-y',
            defaultValue: 'false',
            description: 'Run non-interactively and use defaults.',
          ),
        ],
        examples: [
          'flutter_shadcn init',
          'flutter_shadcn init shadcn --yes',
        ],
        seeAlso: ['registries', 'default', 'sync'],
      ),
      CliCommandMeta(
        id: 'registries',
        description: 'List available and configured registries.',
        sortOrder: 20,
        usage: 'flutter_shadcn registries [flags]',
        flags: [
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: [
          'flutter_shadcn registries',
          'flutter_shadcn registries --json',
        ],
        seeAlso: ['default', 'init'],
      ),
      CliCommandMeta(
        id: 'default',
        description: 'Set or show the default registry namespace.',
        sortOrder: 30,
        usage: 'flutter_shadcn default [namespace]',
        arguments: [
          CliArgumentMeta(
            '[namespace]',
            false,
            'Registry namespace to set as default.',
          ),
        ],
        examples: [
          'flutter_shadcn default',
          'flutter_shadcn default shadcn',
        ],
        seeAlso: ['registries', 'init'],
      ),
      CliCommandMeta(
        id: 'sync',
        description: 'Sync paths and theme from .shadcn/config.json.',
        sortOrder: 40,
        usage: 'flutter_shadcn sync',
        examples: ['flutter_shadcn sync'],
        seeAlso: ['init', 'audit'],
      ),
      CliCommandMeta(
        id: 'project',
        description: 'Project repair and cleanup commands.',
        sortOrder: 45,
        usage: 'flutter_shadcn project <reset|refresh> [flags]',
        arguments: [
          CliArgumentMeta(
            '<reset|refresh>',
            true,
            'Project-scoped maintenance command to run.',
          ),
        ],
        examples: [
          'flutter_shadcn project reset',
          'flutter_shadcn project reset --undo',
          'flutter_shadcn project refresh',
        ],
        notes:
            'Use `project reset` to remove CLI-managed project files with a 24-hour undo window. Use `project refresh` to regenerate missing scaffolding only.',
        seeAlso: ['sync', 'init', 'reset'],
      ),
      CliCommandMeta(
        id: 'assets',
        description: 'Install font and icon assets.',
        sortOrder: 50,
        usage: 'flutter_shadcn assets [flags]',
        flags: [
          CliFlagMeta(
            name: '--icons',
            defaultValue: 'false',
            description: 'Install icon font assets.',
          ),
          CliFlagMeta(
            name: '--typography',
            defaultValue: 'false',
            description: 'Install typography font assets.',
          ),
          CliFlagMeta(
            name: '--fonts',
            defaultValue: 'false',
            description: 'Alias for --typography.',
          ),
          CliFlagMeta(
            name: '--list',
            defaultValue: 'false',
            description: 'List available assets.',
          ),
          CliFlagMeta(
            name: '--all',
            short: '-a',
            defaultValue: 'false',
            description: 'Install all available assets.',
          ),
        ],
        examples: [
          'flutter_shadcn assets --list',
          'flutter_shadcn assets --icons --typography',
        ],
        seeAlso: ['init', 'theme'],
      ),
      CliCommandMeta(
        id: 'theme',
        description: 'Manage registry theme presets.',
        sortOrder: 60,
        usage: 'flutter_shadcn theme [id] [flags]',
        arguments: [
          CliArgumentMeta(
            '[id]',
            false,
            'Theme preset id to apply.',
          ),
        ],
        flags: [
          CliFlagMeta(
            name: '--list',
            defaultValue: 'false',
            description: 'List theme presets.',
          ),
          CliFlagMeta(
            name: '--refresh',
            defaultValue: 'false',
            description: 'Refresh cached theme data.',
          ),
          CliFlagMeta(
            name: '--apply <id>',
            short: '-a',
            description: 'Apply a registry theme preset.',
          ),
          CliFlagMeta(
            name: '--apply-file <path>',
            description: 'Apply a theme from a local JSON file.',
            advanced: true,
          ),
          CliFlagMeta(
            name: '--apply-url <url>',
            description: 'Apply a theme from a JSON URL.',
            advanced: true,
          ),
        ],
        examples: [
          'flutter_shadcn theme --list',
          'flutter_shadcn theme --apply neutral',
          'flutter_shadcn --advanced theme --apply-file theme.json',
        ],
        notes:
            'File and URL theme imports require --advanced. The theme widget subcommand supports widget-level list, list-targets, reset, apply-file, and apply-url workflows.',
        seeAlso: ['assets', 'init'],
      ),
      CliCommandMeta(
        id: 'platform',
        description: 'Configure platform target paths.',
        sortOrder: 70,
        usage: 'flutter_shadcn platform [flags]',
        flags: [
          CliFlagMeta(
            name: '--set <platform.section=path>',
            description: 'Set a platform target path.',
          ),
          CliFlagMeta(
            name: '--reset <platform.section>',
            description: 'Remove a platform target override.',
          ),
          CliFlagMeta(
            name: '--list',
            defaultValue: 'false',
            description: 'List configured platform targets.',
          ),
        ],
        examples: [
          'flutter_shadcn platform --list',
          'flutter_shadcn platform --set ios.runner=ios/Runner',
        ],
        seeAlso: ['init', 'sync'],
      ),
    ],
  ),
  CliCommandGroupMeta(
    title: 'Diagnostics',
    slug: 'diagnostics',
    sortOrder: 30,
    commands: [
      CliCommandMeta(
        id: 'reset',
        description: 'Clear global CLI-managed cache and home-directory state.',
        sortOrder: 5,
        usage: 'flutter_shadcn reset',
        examples: ['flutter_shadcn reset'],
        notes:
            'This command affects only global CLI state under the user home directory. It does not remove project files or uninstall the executable.',
        seeAlso: ['project', 'doctor'],
      ),
      CliCommandMeta(
        id: 'doctor',
        description: 'Diagnose registry resolution and project state.',
        sortOrder: 10,
        usage: 'flutter_shadcn doctor [flags]',
        flags: [
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: ['flutter_shadcn doctor'],
        seeAlso: ['validate', 'audit'],
      ),
      CliCommandMeta(
        id: 'validate',
        description: 'Validate registry integrity.',
        sortOrder: 20,
        usage: 'flutter_shadcn validate [flags]',
        flags: [
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: ['flutter_shadcn validate --json'],
        seeAlso: ['doctor', 'audit'],
      ),
      CliCommandMeta(
        id: 'audit',
        description: 'Audit installed components.',
        sortOrder: 30,
        usage: 'flutter_shadcn audit [flags]',
        flags: [
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: ['flutter_shadcn audit'],
        seeAlso: ['doctor', 'deps'],
      ),
      CliCommandMeta(
        id: 'deps',
        description: 'Compare registry dependencies against pubspec.yaml.',
        sortOrder: 40,
        usage: 'flutter_shadcn deps [component...] [flags]',
        arguments: [
          CliArgumentMeta(
            '[component...]',
            false,
            'Optional component names to check.',
          ),
        ],
        flags: [
          CliFlagMeta(
            name: '--all',
            short: '-a',
            defaultValue: 'false',
            description: 'Compare dependencies for all registry components.',
          ),
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: [
          'flutter_shadcn deps button',
          'flutter_shadcn deps --all',
        ],
        seeAlso: ['audit', 'dry-run'],
      ),
    ],
  ),
  CliCommandGroupMeta(
    title: 'Tooling',
    slug: 'tooling',
    sortOrder: 40,
    commands: [
      CliCommandMeta(
        id: 'feedback',
        description: 'Submit feedback or report issues.',
        sortOrder: 10,
        usage: 'flutter_shadcn feedback [flags]',
        flags: [
          CliFlagMeta(
            name: '--type <type>',
            short: '-t',
            description:
                'Feedback type: bug, feature, docs, question, performance, or other.',
          ),
          CliFlagMeta(
            name: '--title <title>',
            description: 'Issue title.',
          ),
          CliFlagMeta(
            name: '--body <body>',
            description: 'Issue description or body.',
          ),
        ],
        examples: [
          'flutter_shadcn feedback',
          'flutter_shadcn feedback --type bug --title "Install failed"',
        ],
        seeAlso: ['doctor', 'version'],
      ),
      CliCommandMeta(
        id: 'version',
        description: 'Show CLI version.',
        sortOrder: 20,
        usage: 'flutter_shadcn version [flags]',
        flags: [
          CliFlagMeta(
            name: '--check',
            defaultValue: 'false',
            description: 'Check for updates.',
          ),
        ],
        examples: [
          'flutter_shadcn version',
          'flutter_shadcn version --check',
        ],
        seeAlso: ['upgrade'],
      ),
      CliCommandMeta(
        id: 'upgrade',
        description: 'Upgrade the CLI to the latest version.',
        sortOrder: 30,
        usage: 'flutter_shadcn upgrade [flags]',
        flags: [
          CliFlagMeta(
            name: '--force',
            short: '-f',
            defaultValue: 'false',
            description: 'Force upgrade even if already latest.',
          ),
        ],
        examples: [
          'flutter_shadcn upgrade',
          'flutter_shadcn upgrade --force',
        ],
        seeAlso: ['version'],
      ),
    ],
  ),
  CliCommandGroupMeta(
    title: 'Advanced',
    slug: 'advanced',
    sortOrder: 50,
    commands: [
      CliCommandMeta(
        id: 'docs',
        description: 'Regenerate command reference documentation.',
        sortOrder: 10,
        advanced: true,
        usage: 'flutter_shadcn --advanced docs [--generate]',
        flags: [
          CliFlagMeta(
            name: '--generate',
            short: '-g',
            defaultValue: 'false',
            description: 'Regenerate docs/reference/commands.',
          ),
        ],
        examples: ['flutter_shadcn --advanced docs --generate'],
        notes: 'This command requires --advanced.',
        seeAlso: ['install-skill'],
      ),
      CliCommandMeta(
        id: 'install-skill',
        description: 'Install AI skills for local model workflows.',
        sortOrder: 20,
        advanced: true,
        usage: 'flutter_shadcn --advanced install-skill [flags]',
        flags: [
          CliFlagMeta(
            name: '--skill <id>',
            short: '-s',
            description: 'Skill id to install.',
          ),
          CliFlagMeta(
            name: '--model <name>',
            short: '-m',
            description: 'Model name to install for.',
          ),
          CliFlagMeta(
            name: '--skills-url <url-or-path>',
            description: 'Override the skills base URL or local path.',
          ),
          CliFlagMeta(
            name: '--symlink',
            defaultValue: 'false',
            description: 'Symlink a shared skill to the model.',
          ),
          CliFlagMeta(
            name: '--list',
            defaultValue: 'false',
            description: 'List installed skills.',
          ),
          CliFlagMeta(
            name: '--available',
            short: '-a',
            defaultValue: 'false',
            description: 'List available skills from the registry.',
          ),
          CliFlagMeta(
            name: '--interactive',
            short: '-i',
            defaultValue: 'false',
            description: 'Run interactive multi-skill installation.',
          ),
          CliFlagMeta(
            name: '--uninstall <id>',
            description: 'Uninstall a skill.',
          ),
          CliFlagMeta(
            name: '--uninstall-interactive',
            defaultValue: 'false',
            description: 'Run interactive removal.',
          ),
        ],
        examples: [
          'flutter_shadcn --advanced install-skill --available',
          'flutter_shadcn --advanced install-skill --skill flutter-shadcn-cli --model .codex',
          'flutter_shadcn --advanced install-skill --skill flutter-shadcn-ui --model .codex',
          'flutter_shadcn --advanced install-skill --skills-url https://raw.githubusercontent.com/ibrar-x/shadcn_flutter_kit/main/flutter_shadcn_kit/skills --skill flutter-shadcn-ui --model .codex',
        ],
        notes: 'This command requires --advanced.',
        seeAlso: ['docs'],
      ),
    ],
  ),
];
