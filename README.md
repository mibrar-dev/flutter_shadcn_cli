# flutter_shadcn_cli

`flutter_shadcn_cli` is a command-line installer for shadcn-style Flutter component registries. It initializes a Flutter app, resolves components from one or more registries, copies the required files, updates dependencies, and keeps install state in project-local `.shadcn/` metadata.

## Features

- Multi-registry installs with `@namespace/component` addresses.
- Inline registry init actions for bootstrap files such as app and localization helpers.
- Dependency-aware component installs with shared-file de-duplication.
- Per-component locale resource merging into app ARB files.
- Registry manifest-first resolution with fallback to configured component indexes.
- Project diagnostics for registry, config, dependency, and installed-file drift.
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

## Quick Start

Run commands from the root of an existing Flutter project:

```bash
flutter_shadcn init --yes
flutter_shadcn add button
```

Use a qualified component address when a project has more than one enabled registry:

```bash
flutter_shadcn add @shadcn/button
```

If an unqualified component name exists in more than one enabled registry, `add` fails and asks for the explicit `@namespace/component` address.

## Common Workflows

List and inspect available registry content:

```bash
flutter_shadcn registries
flutter_shadcn list
flutter_shadcn search button
flutter_shadcn info @shadcn/button
```

Preview, install, and remove components:

```bash
flutter_shadcn dry-run button
flutter_shadcn add button card alert
flutter_shadcn remove alert
```

Install optional assets after init:

```bash
flutter_shadcn assets --list
flutter_shadcn assets --icons
flutter_shadcn assets --font
```

Create or refresh localization support:

```bash
flutter_shadcn locale init
flutter_shadcn locale add en
```

Diagnose project state:

```bash
flutter_shadcn doctor
flutter_shadcn validate
flutter_shadcn audit
flutter_shadcn deps
```

## Multi-Registry Behavior

`flutter_shadcn` stores registry configuration in `.shadcn/config.json`, install state in `.shadcn/state.json`, per-component install manifests in `.shadcn/components/`, and v1 source records in `shadcn.lock`.

The v1 resolver uses the component manifest published by a registry as the source of truth. If a registry does not publish per-component manifests, the CLI falls back to the configured component index paths for that registry.

## JSON and Exit Codes

Automation-friendly commands support `--json`:

```bash
flutter_shadcn doctor --json
flutter_shadcn validate --json
flutter_shadcn info @shadcn/button --json
```

The process exit code is also returned in `meta.exitCode` for JSON-capable commands. See [docs/reference/exit-codes.md](docs/reference/exit-codes.md) for the full exit-code table.

## Example

The [example](example/flutter_shadcn_cli_example.dart) script demonstrates the small public Dart API exported by the package for inspecting bundled theme preset metadata:

```bash
dart run example/flutter_shadcn_cli_example.dart
```

Most users should run the CLI executables instead of importing the package.

## Documentation

- [User guide](https://github.com/ibrar-x/flutter_shadcn_cli/tree/main/docs/index.md)
- [Testing guide](https://github.com/ibrar-x/flutter_shadcn_cli/tree/main/docs/testing-guide.md)
- [Command reference](https://github.com/ibrar-x/flutter_shadcn_cli/tree/main/docs/reference/commands/index.md)
- [Exit codes](https://github.com/ibrar-x/flutter_shadcn_cli/tree/main/docs/reference/exit-codes.md)
- [Registry directory reference](https://github.com/ibrar-x/flutter_shadcn_cli/tree/main/docs/reference/registries-json.md)
- [Inline init actions](https://github.com/ibrar-x/flutter_shadcn_cli/tree/main/docs/reference/inline-init-actions.md)

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
