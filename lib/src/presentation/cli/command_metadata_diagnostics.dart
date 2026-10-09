import 'package:flutter_shadcn_cli/src/presentation/cli/command_metadata_models.dart';

/// The Diagnostics command group (`reset`, `doctor`, `validate`, `audit`).
const CliCommandGroupMeta diagnosticsCommandGroup = CliCommandGroupMeta(
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
);
