---
name: flutter-shadcn-cli
description: Use when maintaining, testing, documenting, or automating the flutter_shadcn CLI, multi-registry resolution, inline init actions, diagnostics, skill installation, or pub.dev packaging behavior.
---

# Flutter shadcn CLI

`flutter_shadcn` is the installer and maintenance CLI for Flutter shadcn registries. Treat CLI commands, tests, docs, and registry schemas as one product surface.

## Start Here

Run from the CLI repo root before changing behavior:

```bash
dart pub get
dart run bin/flutter_shadcn.dart --help
dart test
```

For architecture questions, read `graphify-out/GRAPH_REPORT.md` first. Use `graphify query`, `graphify path`, or `graphify explain` for cross-module relationships. After modifying code, run `graphify update .`.

## Non-Negotiables

- Do not guess flags. Check `dart run bin/flutter_shadcn.dart --help` and command help.
- Preserve single-registry compatibility while changing multi-registry behavior.
- Keep namespace behavior deterministic: prefer `@namespace/component` in scripts, docs, tests, and AI output.
- Preview installs with `dry-run --json` before non-trivial `add` operations.
- Never bypass path safety in init actions. Reject traversal and writes outside the project.
- Keep docs, generated command metadata, tests, and behavior in sync.
- Ship AI skills with the packaged CLI under `registry/skills` so pub.dev users can install them.

## Core Workflows

### Maintain CLI Behavior

1. Read the existing command implementation in `lib/src/presentation/cli/commands/`.
2. Read lower-level services in `lib/src/application`, `lib/src/infrastructure`, and compatibility exports in `lib/src/*.dart`.
3. Write or update a focused test in `test/` before implementation.
4. Run the specific test, then the relevant command manually with `dart run bin/flutter_shadcn.dart`.
5. Update `docs/user/`, `docs/developer/`, and `lib/src/presentation/cli/command_metadata.dart` when public behavior changes.

### Validate A Registry-Aware Change

```bash
dart test test/resolver_v1_test.dart
dart test test/multi_registry_manager_test.dart
dart test test/e2e_multi_registry_fixture_test.dart
dart run bin/flutter_shadcn.dart registries --json
dart run bin/flutter_shadcn.dart doctor --json
```

### Validate Skill Installer Changes

```bash
dart test test/skill_manager_test.dart
dart run bin/flutter_shadcn.dart --advanced install-skill --available
dart run bin/flutter_shadcn.dart --advanced install-skill --skill flutter-shadcn-cli --model .codex
dart run bin/flutter_shadcn.dart --advanced install-skill --skill flutter-shadcn-ui --model .codex
```

## Command Map

Use [references/commands.md](references/commands.md) for public commands, advanced flags, and machine-readable outputs.

## Architecture Map

Use [references/architecture.md](references/architecture.md) for resolver, config/state, init actions, installer, diagnostics, docs, and skill packaging responsibilities.

## Test Discipline

Use [references/testing.md](references/testing.md) for targeted tests and expected coverage by change type.

## Skill Packaging

Use [references/skills-packaging.md](references/skills-packaging.md) before editing `registry/skills`, `install-skill`, `SkillsLoader`, or `SkillManager`.
