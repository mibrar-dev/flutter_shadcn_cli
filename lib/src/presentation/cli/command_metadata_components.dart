import 'package:flutter_shadcn_cli/src/presentation/cli/command_metadata_models.dart';

/// The Components command group (`add`, `remove`, `update`, ...).
const CliCommandGroupMeta componentsCommandGroup = CliCommandGroupMeta(
  title: 'Components',
  slug: 'components',
  sortOrder: 10,
  commands: [
    CliCommandMeta(
      id: 'add',
      description: 'Install one or more components or blocks and their '
          'closure.',
      sortOrder: 10,
      usage: 'flutter_shadcn add <component|block...> [flags]',
      arguments: [
        CliArgumentMeta(
          '<component|block...>',
          true,
          'Component or block names, or @namespace/component addresses.',
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
          name: '--blocks',
          defaultValue: 'false',
          description: 'With --all, install every block too.',
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
        'flutter_shadcn add login-01',
        'flutter_shadcn add input select tabs',
        'flutter_shadcn add --all --blocks',
      ],
      notes:
          'Installs the transitive closure: requested components and blocks, their components/primitives deps, and the always-on foundation + theme core. A block lands in blocks/<id>/ together with the components it uses. User-owned <name>_theme.dart files are never overwritten.',
      seeAlso: ['remove', 'update', 'list', 'info', 'dry-run'],
    ),
    CliCommandMeta(
      id: 'remove',
      description: 'Remove installed components, blocks and orphaned layer '
          'files.',
      sortOrder: 20,
      aliases: ['rm'],
      usage: 'flutter_shadcn remove <component|block...> [flags]',
      arguments: [
        CliArgumentMeta(
          '<component|block...>',
          false,
          'Installed component or block names to remove.',
        ),
      ],
      flags: [
        CliFlagMeta(
          name: '--all',
          short: '-a',
          defaultValue: 'false',
          description: 'Remove every installed component and block.',
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
      examples: [
        'flutter_shadcn remove button',
        'flutter_shadcn remove login-01',
        'flutter_shadcn rm dialog',
      ],
      notes:
          'Refuses while another installed component or block still needs the target, unless --force. A block owns no user-owned file, so removing one deletes every path it recorded.',
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
      description: 'List available components or blocks, by category.',
      sortOrder: 50,
      aliases: ['ls'],
      usage: 'flutter_shadcn list [--blocks] [--category <name>] [--json]',
      flags: [
        CliFlagMeta(
          name: '--blocks',
          defaultValue: 'false',
          description: 'List the blocks layer instead of components.',
        ),
        CliFlagMeta(
          name: '--category <name>',
          defaultValue: 'false',
          description: 'Only entries of that category.',
        ),
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
      ],
      examples: [
        'flutter_shadcn list',
        'flutter_shadcn list --blocks',
        'flutter_shadcn list --category "Forms & Inputs"',
        'flutter_shadcn ls --json',
      ],
      notes:
          'Human output groups entries by the category each meta.json declares; the JSON envelope keeps both `components` and `blocks` so a consumer never has to probe for a key.',
      seeAlso: ['search', 'info', 'add'],
    ),
    CliCommandMeta(
      id: 'search',
      description: 'Search components and blocks by name, description or tag.',
      sortOrder: 60,
      usage: 'flutter_shadcn search <query> [--category <name>] [--json]',
      arguments: [CliArgumentMeta('<query>', true, 'Search text.')],
      flags: [
        CliFlagMeta(
          name: '--category <name>',
          defaultValue: 'false',
          description: 'Only entries of that category.',
        ),
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
      ],
      examples: [
        'flutter_shadcn search button',
        'flutter_shadcn search login --category Authentication',
      ],
      notes:
          'Both kinds are searched at once, because `add <id>` resolves both. Each result carries its `kind`, `category` and, for a block, its `viewport`.',
      seeAlso: ['list', 'info'],
    ),
    CliCommandMeta(
      id: 'info',
      description: 'Show a component\'s or block\'s closure, files and api.',
      sortOrder: 70,
      aliases: ['i'],
      usage: 'flutter_shadcn info <component|block> [--json]',
      arguments: [
        CliArgumentMeta(
          '<component|block>',
          true,
          'Component or block name, or @namespace/component address.',
        ),
      ],
      flags: [
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
      ],
      examples: [
        'flutter_shadcn info button',
        'flutter_shadcn info login-01',
        'flutter_shadcn i dialog',
      ],
      notes:
          'A component reports its api and user-owned theme files; a block reports its viewport, its own files and the components it assembles.',
      seeAlso: ['list', 'search', 'add'],
    ),
  ],
);
