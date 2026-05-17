# Generated Theme Artifact Redesign

Date: 2026-05-03

## Problem

The current CLI executes registry-provided Dart during `init` and `theme` operations via `themeConverterDart`. That is the unsafe behavior to remove.

## Findings

- `shadcn_flutter_cli` currently executes registry converter code in:
  - `lib/src/application/services/installer/installer_theme_part.dart`
  - `lib/src/infrastructure/registry/registry_theme_converter_client.dart`
  - `lib/src/infrastructure/registry/theme_preset_loader.dart`
  - `lib/src/application/services/multi_registry/multi_registry_init_part.dart`
- `registry-directory` currently publishes `paths.themeConverterDart` in schema and official registry metadata.
- `shadcn_flutter_kit` already has publish-time theme tooling under `flutter_shadcn_kit/tool/theme/`, but it currently generates the old preset index shape and also contains the converter script used by the CLI.

## Recommended Design

### Contract

Replace runtime conversion with a generated-artifact contract:

`theme selection -> list of generated files`

Registry publishes:
- `paths.themesJson`
- optional `paths.themesSchemaJson`
- no `themeConverterDart`

Each theme entry contains:
- `name`
- `label`
- optional `description`
- optional `source`
- `files[]` with:
  - `source`
  - `target`
  - `sha256`

### CLI behavior

- `init` and `theme --apply <id>`:
  - fetch `themesJson`
  - prompt/select theme
  - download all generated files for selected theme
  - verify SHA-256 for every file
  - validate every target path before writing anything
  - write all files only after the full set passes
  - record installed theme files in project manifest/state
- `theme --list` remains index-driven.
- Remove raw JSON theme ingestion flows:
  - `theme --apply-file`
  - `theme --apply-url`
  - `theme widget --apply-file`
  - `theme widget --apply-url`
  - widget converter-driven list/reset flows tied to registry code execution

### Tooling behavior

Move conversion fully to registry publish/build time:
- keep generator logic in `shadcn_flutter_kit/tool/theme/`
- stop exposing it to the CLI as runtime code
- generate:
  - generated Dart artifact files per theme
  - `themes/index.json`-style manifest with hashes

## Commit sequence

1. `refactor(schema): remove runtime theme converter fields`
2. `feat(schema): add generated theme artifact contract`
3. `refactor(registry): publish generated theme artifact metadata`
4. `refactor(tooling): generate theme artifact manifests and hashes`
5. `refactor(cli): install generated theme artifacts safely`
6. `test(cli): cover generated theme artifact installation`
7. `docs(registry): document generated theme artifact contract`

## Risk notes

- Existing advanced theme file/url commands cannot be preserved without reintroducing unsafe runtime interpretation. Removing them is the clean break.
- Multi-file theme installs need all-or-nothing validation before writes.
- Official registry tooling must emit hashes deterministically so CLI cache keys remain stable.
