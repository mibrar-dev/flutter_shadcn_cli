import 'package:flutter_shadcn_cli/src/presentation/cli/command_metadata_models.dart';

/// The Project command group (`init`, `registries`, `theme`, ...).
const CliCommandGroupMeta projectCommandGroup = CliCommandGroupMeta(
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
);
