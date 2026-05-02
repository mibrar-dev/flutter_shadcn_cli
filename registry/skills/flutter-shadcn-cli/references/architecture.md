# CLI Architecture Map

## Entry Points

- `bin/flutter_shadcn.dart`: public executable.
- `bin/shadcn.dart`: alias executable.
- `lib/src/presentation/cli/bootstrap.dart`: command dispatch setup.
- `lib/src/presentation/cli/cli_parser.dart`: command and flag parsing.
- `lib/src/presentation/cli/command_metadata.dart`: generated/user-visible command reference source.

## Registry And Resolution

- `runtime_roots.dart`: finds package root, local registry roots, source checkouts, and pub-cache package registry.
- `registry_selection.dart`: resolves active registry source and namespace.
- `resolver_v1.dart` and `lib/src/infrastructure/resolver/v1/`: component reference resolution and path safety.
- `multi_registry_manager.dart`: multi-registry state and directory handling.
- `registry_directory.dart` and `lib/src/infrastructure/registry_directory/`: `registries.json` loading and schema validation.

## Project State

- `.shadcn/config.json`: registry config, paths, aliases, platform targets.
- `.shadcn/state.json`: installed component state and managed dependency bookkeeping.
- `.shadcn/components/*.json`: per-component install manifests.
- Migration must preserve legacy single-registry projects.

## Install And Init

- `installer.dart`: component install/remove/sync behavior.
- `init_action_engine.dart`: inline registry `init.actions`.
- `inline_action_journal.dart`: tracks actions.
- Path writes must be project-contained and reject traversal.

## Diagnostics

- `doctor`: project and registry configuration health.
- `validate`: registry structure, schema, and file references.
- `audit`: installed files versus registry metadata.
- `deps`: registry dependency requirements versus `pubspec.yaml`.

## Skills

- Bundled skills live under `registry/skills`.
- `SkillsLoader` finds `skills.json` from bundled package paths and compatibility local paths.
- `SkillManager` installs AI-facing files declared in `skill.json`; it does not copy management schemas or manifest files into model folders.
- Remote skill sources support `--skills-url` and GitHub tree URLs normalized to raw file URLs.

## Docs

- User docs: `docs/user/`.
- Developer docs: `docs/developer/`.
- Guides: `docs/guides/`.
- Generated reference: `docs/reference/`.
- If command behavior changes, update docs and command metadata in the same change.
