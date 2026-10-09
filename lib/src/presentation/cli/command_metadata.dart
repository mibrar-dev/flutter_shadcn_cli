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
        description: 'Install one or more components and their closure.',
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
            name: '--dry-run',
            defaultValue: 'false',
            description: 'Print the plan without writing anything.',
          ),
          CliFlagMeta(
            name: '--force',
            short: '-f',
            defaultValue: 'false',
            description: 'Overwrite locally modified registry files.',
          ),
          CliFlagMeta(
            name: '--include-preview',
            defaultValue: 'false',
            description: 'Also copy each component preview.dart.',
          ),
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: [
          'flutter_shadcn add button',
          'flutter_shadcn add input select tabs',
          'flutter_shadcn add --all',
        ],
        notes:
            'Installs the transitive closure: requested components, their components/primitives deps, and the always-on foundation + theme core. User-owned <name>_theme.dart files are never overwritten.',
        seeAlso: ['remove', 'update', 'list', 'info', 'dry-run'],
      ),
      CliCommandMeta(
        id: 'remove',
        description: 'Remove installed components and orphaned layer files.',
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
            description: 'Remove every installed component.',
          ),
          CliFlagMeta(
            name: '--force',
            short: '-f',
            defaultValue: 'false',
            description: 'Remove even when dependents remain.',
          ),
          CliFlagMeta(
            name: '--purge-user-themes',
            defaultValue: 'false',
            description: 'Also delete <name>_theme.dart user files.',
          ),
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: ['flutter_shadcn remove button', 'flutter_shadcn rm dialog'],
        seeAlso: ['add', 'list'],
      ),
      CliCommandMeta(
        id: 'update',
        description: 'Update installed components from the registry.',
        sortOrder: 30,
        usage: 'flutter_shadcn update [component...] [flags]',
        arguments: [
          CliArgumentMeta(
            '[component...]',
            false,
            'Components to update (default: all installed).',
          ),
        ],
        flags: [
          CliFlagMeta(
            name: '--all',
            short: '-a',
            defaultValue: 'false',
            description: 'Update every installed component.',
          ),
          CliFlagMeta(
            name: '--check',
            defaultValue: 'false',
            description: 'Report only; exit 1 when behind or modified.',
          ),
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: [
          'flutter_shadcn update',
          'flutter_shadcn update button',
          'flutter_shadcn update --check',
        ],
        notes:
            'Hash-driven: files whose bytes still match shadcn.lock are overwritten with the manifest\'s current content, locally modified files are reported and left, and user-owned theme files are never touched.',
        seeAlso: ['add', 'audit', 'doctor'],
      ),
      CliCommandMeta(
        id: 'dry-run',
        description: 'Preview what add would install.',
        sortOrder: 40,
        usage: 'flutter_shadcn dry-run <component...> [flags]',
        arguments: [
          CliArgumentMeta(
            '<component...>',
            false,
            'Components to preview.',
          ),
        ],
        flags: [
          CliFlagMeta(
            name: '--all',
            short: '-a',
            defaultValue: 'false',
            description: 'Preview every component.',
          ),
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: ['flutter_shadcn dry-run button'],
        seeAlso: ['add'],
      ),
      CliCommandMeta(
        id: 'list',
        description: 'List available components.',
        sortOrder: 50,
        aliases: ['ls'],
        usage: 'flutter_shadcn list [--json]',
        flags: [
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: ['flutter_shadcn list', 'flutter_shadcn ls --json'],
        seeAlso: ['search', 'info', 'add'],
      ),
      CliCommandMeta(
        id: 'search',
        description: 'Search components by name, description or tag.',
        sortOrder: 60,
        usage: 'flutter_shadcn search <query> [--json]',
        arguments: [CliArgumentMeta('<query>', true, 'Search text.')],
        flags: [
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: ['flutter_shadcn search button'],
        seeAlso: ['list', 'info'],
      ),
      CliCommandMeta(
        id: 'info',
        description: 'Show a component\'s closure, files and api.',
        sortOrder: 70,
        aliases: ['i'],
        usage: 'flutter_shadcn info <component> [--json]',
        arguments: [
          CliArgumentMeta(
            '<component>',
            true,
            'Component name or @namespace/component address.',
          ),
        ],
        flags: [
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: ['flutter_shadcn info button', 'flutter_shadcn i dialog'],
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
        description: 'Install the layer core and generate the app theme.',
        sortOrder: 10,
        usage: 'flutter_shadcn init [flags]',
        flags: [
          CliFlagMeta(
            name: '--dir <path>',
            description: 'Install root (default: lib/ui/shadcn).',
          ),
          CliFlagMeta(
            name: '--theme <id>',
            description: 'Theme preset id (default: vercel).',
          ),
          CliFlagMeta(
            name: '--yes',
            short: '-y',
            defaultValue: 'false',
            description: 'Non-interactive; use the default preset.',
          ),
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: [
          'flutter_shadcn init',
          'flutter_shadcn init --theme vercel --yes',
        ],
        notes:
            'Copies every foundation and theme unit (no component), writes .shadcn/config.json and shadcn.lock v2, and generates <installRoot>/theme/app_theme.dart from the chosen preset.',
        seeAlso: ['registries', 'default', 'theme', 'add'],
      ),
      CliCommandMeta(
        id: 'registries',
        description: 'List configured and discoverable registries.',
        sortOrder: 20,
        usage: 'flutter_shadcn registries [--json]',
        flags: [
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: ['flutter_shadcn registries'],
        seeAlso: ['default', 'init'],
      ),
      CliCommandMeta(
        id: 'default',
        description: 'Set or show the default registry namespace.',
        sortOrder: 30,
        usage: 'flutter_shadcn default [namespace] [--local | --remote]',
        arguments: [
          CliArgumentMeta('[namespace]', false, 'Namespace to set as default.'),
        ],
        examples: [
          'flutter_shadcn default',
          'flutter_shadcn default shadcn --remote',
        ],
        seeAlso: ['registries', 'init'],
      ),
      CliCommandMeta(
        id: 'sync',
        description: 'Re-apply the installed closure and locked theme.',
        sortOrder: 40,
        usage: 'flutter_shadcn sync',
        examples: ['flutter_shadcn sync'],
        seeAlso: ['init', 'audit', 'update'],
      ),
      CliCommandMeta(
        id: 'project',
        description: 'Project repair and cleanup commands.',
        sortOrder: 50,
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
            '`project reset` removes CLI-managed files with a 24-hour undo window. `project refresh` re-applies the installed closure and locked theme.',
        seeAlso: ['sync', 'init', 'reset'],
      ),
      CliCommandMeta(
        id: 'theme',
        description: 'List and apply registry theme presets.',
        sortOrder: 60,
        usage: 'flutter_shadcn theme <list|apply <preset>> [flags]',
        arguments: [
          CliArgumentMeta('<list|apply>', false, 'Theme action to run.'),
        ],
        flags: [
          CliFlagMeta(
            name: '--refresh',
            defaultValue: 'false',
            description: 'Overwrite app_theme.dart even when edited.',
          ),
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: [
          'flutter_shadcn theme list',
          'flutter_shadcn theme apply vercel',
        ],
        notes:
            'app_theme.dart is user-owned: without --refresh a locally modified file is reported as drift and left untouched.',
        seeAlso: ['init', 'add'],
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
        seeAlso: ['project', 'doctor'],
      ),
      CliCommandMeta(
        id: 'doctor',
        description: 'Diagnose the manifest, closure, layout and lock drift.',
        sortOrder: 10,
        usage: 'flutter_shadcn doctor [--json]',
        flags: [
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: ['flutter_shadcn doctor'],
        notes:
            'Exit codes: 0 clean, 1 drift/modified, 2 broken closure, 3 manifest invalid.',
        seeAlso: ['validate', 'audit', 'update'],
      ),
      CliCommandMeta(
        id: 'validate',
        description: 'Validate the registry manifest against the v2 schema.',
        sortOrder: 20,
        usage: 'flutter_shadcn validate [--json]',
        flags: [
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: ['flutter_shadcn validate'],
        seeAlso: ['doctor', 'audit'],
      ),
      CliCommandMeta(
        id: 'audit',
        description: 'Compare installed files against shadcn.lock.',
        sortOrder: 30,
        usage: 'flutter_shadcn audit [--json]',
        flags: [
          CliFlagMeta(
            name: '--json',
            defaultValue: 'false',
            description: 'Output machine-readable JSON.',
          ),
        ],
        examples: ['flutter_shadcn audit'],
        seeAlso: ['doctor', 'update'],
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
            description: 'Feedback type: bug, feature, docs, question, other.',
          ),
          CliFlagMeta(name: '--title <title>', description: 'Issue title.'),
          CliFlagMeta(name: '--body <body>', description: 'Issue body.'),
        ],
        examples: ['flutter_shadcn feedback'],
        seeAlso: ['doctor', 'version'],
      ),
      CliCommandMeta(
        id: 'version',
        description: 'Show the CLI version.',
        sortOrder: 20,
        usage: 'flutter_shadcn version [--check]',
        flags: [
          CliFlagMeta(
            name: '--check',
            defaultValue: 'false',
            description: 'Check for updates.',
          ),
        ],
        examples: ['flutter_shadcn version --check'],
        seeAlso: ['upgrade'],
      ),
      CliCommandMeta(
        id: 'upgrade',
        description: 'Upgrade the CLI to the latest version.',
        sortOrder: 30,
        usage: 'flutter_shadcn upgrade [--force]',
        flags: [
          CliFlagMeta(
            name: '--force',
            short: '-f',
            defaultValue: 'false',
            description: 'Force upgrade even if already latest.',
          ),
        ],
        examples: ['flutter_shadcn upgrade'],
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
            description: 'Regenerate doc/reference/commands.',
          ),
        ],
        examples: ['flutter_shadcn --advanced docs --generate'],
        notes: 'This command requires --advanced.',
      ),
    ],
  ),
];
