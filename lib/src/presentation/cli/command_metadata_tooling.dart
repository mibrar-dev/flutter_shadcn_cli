import 'package:flutter_shadcn_cli/src/presentation/cli/command_metadata_models.dart';

/// The Tooling command group (`feedback`, `version`, `upgrade`).
const CliCommandGroupMeta toolingCommandGroup = CliCommandGroupMeta(
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
);

/// The Advanced command group (`docs`, behind `--advanced`).
const CliCommandGroupMeta advancedCommandGroup = CliCommandGroupMeta(
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
);
