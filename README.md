# flutter_shadcn_cli

`flutter_shadcn_cli` is a command-line installer for shadcn-style Flutter component registries. It initializes a Flutter app with the shared foundation + theme layers, resolves components and their dependency closure from a registry, copies the required files, adds missing pub packages, and keeps install state in a project-local `shadcn.lock` (lockfileVersion 2).

## Features

- Layer-aware installs: `foundation/`, `theme/` and `primitives/` are pulled in as a dependency closure, never addressed as components.
- Transitive component closure with a single-owner symbol preflight.
- Hash-driven `update`: overwrite unchanged files, report local edits, install files the registry added, and never touch user-owned `<name>_theme.dart` files.
- Registry theme presets: `theme list` / `theme apply` generate a values-only `<installRoot>/theme/app_theme.dart`.
- Remote registry by default (GitHub raw at the CLI version's ref), with `--registry <path|url>` and an offline cache.
- Diagnostics for the manifest, closure, layout, lock drift and pub dependencies.
- JSON output and documented exit codes for scripts and CI.

## Installation

Activate the CLI globally:

```bash
dart pub global activate flutter_shadcn_cli
```

Make sure the Dart pub cache bin directory is on your `PATH`. Then verify the executable:

```bash
flutter_shadcn version
```

The package also exposes `shadcn` as a shorter executable alias.

Installed components carry no per-file `// @dart=` language pins, so the app
they land in must declare `environment: sdk: ^3.12.0` or newer — the newest
language feature the registry uses shipped in Dart 3.12.0. See
[doc/user/complete-guide.md](doc/user/complete-guide.md) for the full
requirements list.

## Quick Start

Run commands from the root of an existing Flutter project:

```bash
flutter_shadcn init --yes
flutter_shadcn add button
```

`init` copies the always-on foundation + theme core, writes `.shadcn/config.json` and `shadcn.lock`, and generates the app theme from a preset (`neutral` by default).

Point the CLI at a local registry checkout while developing a registry:

```bash
flutter_shadcn --registry ../shadcn_flutter_kit/flutter_shadcn_kit/lib/registry init --yes
```

## Common Workflows

List and inspect available registry content:

```bash
flutter_shadcn list
flutter_shadcn list --blocks
flutter_shadcn list --category "Forms & Inputs"
flutter_shadcn search button
flutter_shadcn info button
flutter_shadcn info login-01
```

Preview, install, update and remove components or blocks:

```bash
flutter_shadcn dry-run button
flutter_shadcn add button card alert
flutter_shadcn add login-01
flutter_shadcn update --check
flutter_shadcn update button
flutter_shadcn remove alert
flutter_shadcn remove login-01
```

Themes:

```bash
flutter_shadcn theme list
flutter_shadcn theme apply tangerine
flutter_shadcn theme apply tangerine --refresh
```

Diagnose project state:

```bash
flutter_shadcn doctor
flutter_shadcn validate
flutter_shadcn audit
```

## Blocks

A **block** is a ready-made, installable screen (`login-01`, `dashboard-01`,
`sidebar-07`, ...) assembled from components. Blocks are a fourth registry
layer under `blocks/`, and `add <id>` resolves a component and a block alike:

```bash
flutter_shadcn add login-01        # the block + every component it needs
flutter_shadcn add --all --blocks  # all components and all blocks
```

- a block installs to `lib/ui/shadcn/blocks/<id>/`, together with the
  transitive components, primitives, theme and foundation units it imports;
- `shadcn.lock` records installed blocks (a `blocks[]` array with their file
  hashes and closure), so `update`, `remove`, `sync`, `audit` and `doctor`
  all see them;
- a block owns **no** user-owned file: `update` may always refresh a block
  file whose bytes still match the lock, exactly as for a component;
- removing a block deletes only its own files; the components it assembled
  stay installed. Removing a component a block still needs is refused unless
  `--force`;
- `list --blocks`, `search` and `info <block>` report the block's `category`
  and `viewport`; block docs (`blocks/<id>/README.md`) are never copied into
  an app.

## Install Layout

Every install keeps the registry's directory depth so the relative imports inside the copied files stay valid:

```
lib/ui/shadcn/
  foundation/…               # shared primitives
  theme/…                    # theme tokens + the generated app_theme.dart
  primitives/…               # UI primitives
  components/<name>/        # one directory per installed component
  blocks/<id>/              # one directory per installed block
```…        # one directory per installed component
```

`<name>_theme.dart` files are **user-owned**: `add`, `update` and `remove` never overwrite or delete them unless `remove --purge-user-themes` is given.

## Registry and Install State

`flutter_shadcn` resolves a registry manifest (`manifests/registry.json`, schemaVersion 2) from the remote registry by default, or from `--registry <path|url>`. Remote reads are cached under `.shadcn/cache/registry` for offline re-installs (`--offline`).

Project state lives in two files:

- `.shadcn/config.json` — the install path, the selected theme id and the registry source.
- `shadcn.lock` — lockfileVersion 2: the registry reference, the install root, the theme selection, the layer units/files, each component's files, user-owned files and public symbols, and each installed block's files and closure.

## JSON and Exit Codes

Automation-friendly commands support `--json`:

```bash
flutter_shadcn doctor --json
flutter_shadcn validate --json
flutter_shadcn info button --json
```

The process exit code is also returned in `meta.exitCode` for JSON-capable commands. See [doc/reference/exit-codes.md](doc/reference/exit-codes.md) for the full exit-code table.

## Example

The [example](example/flutter_shadcn_cli_example.dart) script demonstrates the small public Dart API exported by the package for inspecting bundled theme preset metadata:

```bash
dart run example/flutter_shadcn_cli_example.dart
```

Most users should run the CLI executables instead of importing the package.

## Documentation

- User guide: [doc/index.md](doc/index.md)
- Getting started: [doc/user/getting-started.md](doc/user/getting-started.md)
- Complete guide: [doc/user/complete-guide.md](doc/user/complete-guide.md)
- Developer / local registry development: [doc/developer/local-registry-development.md](doc/developer/local-registry-development.md)
- Testing guide: [doc/testing-guide.md](doc/testing-guide.md)
- Command reference: [doc/reference/commands/index.md](doc/reference/commands/index.md)
- Exit codes: [doc/reference/exit-codes.md](doc/reference/exit-codes.md)

## Publishing Checks

Before publishing, run:

```bash
dart format --set-exit-if-changed .
dart analyze
dart test
dart pub publish --dry-run
```

The dry run prints every file that would be uploaded to pub.dev. Cancel publishing if internal reports, caches, generated graph data, or local-only artifacts appear in that list.

## License

This package is released under the BSD 3-Clause license. See [LICENSE](LICENSE).
