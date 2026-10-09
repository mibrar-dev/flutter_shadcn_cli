# Commands

This page explains every public command in `flutter_shadcn`. The CLI installs components and their layer closure from a registry manifest (schemaVersion 2), keeps install state in `shadcn.lock` (lockfileVersion 2), and resolves the registry remotely by default.

For the full installation-to-production workflow, read the [complete user guide](complete-guide.md).

## Global Options

Global options appear before the command.

```bash
flutter_shadcn --verbose add button
flutter_shadcn --offline list
flutter_shadcn --registry ../shadcn_flutter_kit/flutter_shadcn_kit/lib/registry init --yes
flutter_shadcn --registry https://example.com/registry validate
```

Options:

- `--verbose`, `-v`: print more detail while commands run.
- `--offline`: disable network calls and use the cached registry only.
- `--registry <path|url>`: override the registry source with a local directory or an `http(s)` URL.
- `--registry-name <namespace>`: select the registry namespace.
- `--advanced`: show and enable developer commands (for example `docs`).
- `--help`, `-h`: show help.

## `init`

Installs the always-on foundation + theme core and generates the app theme.

```bash
flutter_shadcn init
flutter_shadcn init --theme vercel --yes
flutter_shadcn init --dir lib/shadcn --yes
```

What it does:

- copies every `foundation/` and `theme/` unit (no component)
- writes `.shadcn/config.json` and `shadcn.lock` (lockfileVersion 2)
- generates `<installRoot>/theme/app_theme.dart` from the chosen preset

Options:

- `--dir <path>`: install root (default `lib/ui/shadcn`).
- `--theme <id>`: theme preset id (default `vercel`).
- `--yes`, `-y`: run non-interactively and use the default preset.
- `--json`: print machine-readable output.

## `add`

Installs one or more components and their transitive closure.

```bash
flutter_shadcn add button
flutter_shadcn add button dialog input select calendar
flutter_shadcn add --all
```

What it does:

- resolves the closure: requested components, their component/primitive deps, and the foundation + theme core
- refuses an install that would define the same public symbol twice
- copies files verbatim into the depth-preserving layout
- adds missing pub packages to `pubspec.yaml` and runs `flutter pub get`
- updates `shadcn.lock`

Options:

- `--all`, `-a`: install every available component.
- `--dry-run`: print the plan without writing anything.
- `--force`, `-f`: overwrite locally modified registry files.
- `--include-preview`: also copy each component's `preview.dart`.
- `--json`: print machine-readable output.

User-owned `<name>_theme.dart` files are never overwritten.

## `remove`

Removes installed components and any layer file no remaining install needs.

```bash
flutter_shadcn remove button
flutter_shadcn remove --all
flutter_shadcn remove button --purge-user-themes
```

Options:

- `--all`, `-a`: remove every installed component.
- `--force`, `-f`: remove even when dependents remain.
- `--purge-user-themes`: also delete `<name>_theme.dart` user files.
- `--json`: print machine-readable output.

Without `--force`, the CLI protects a component that another installed component still depends on. Without `--purge-user-themes`, user-owned theme files stay on disk.

## `update`

Updates installed components to the registry's current files.

```bash
flutter_shadcn update
flutter_shadcn update button
flutter_shadcn update --check
```

What it does:

- overwrites registry-owned files whose bytes still match `shadcn.lock`
- installs files the manifest has added since the install (and their new layer deps)
- reports locally modified files and leaves them untouched
- adds new pub packages the closure needs
- regenerates `app_theme.dart` from the locked preset

Options:

- `--all`, `-a`: update every installed component.
- `--check`: report only; exit `1` when anything is behind or modified.
- `--json`: print machine-readable output.

`update` never reads or writes user-owned `<name>_theme.dart` files.

## `dry-run`

Shows what `add` would do without writing files.

```bash
flutter_shadcn dry-run button
flutter_shadcn dry-run --all --json
```

Options:

- `--all`, `-a`: include every registry component.
- `--json`: print machine-readable output.

## `list`

Lists available components in the registry.

```bash
flutter_shadcn list
flutter_shadcn list --json
```

Options:

- `--json`: print machine-readable output.

## `search`

Searches registry components by name, description, or tags.

```bash
flutter_shadcn search button
flutter_shadcn search form --json
```

Options:

- `--json`: print machine-readable output.

## `info`

Shows a component's closure, files and public API.

```bash
flutter_shadcn info button
flutter_shadcn info button --json
```

Options:

- `--json`: print machine-readable output.

The `import` field is computed from the install root and the component entry, so it matches the real install layout.

## `theme`

Lists or applies registry theme presets.

```bash
flutter_shadcn theme list
flutter_shadcn theme apply vercel
flutter_shadcn theme apply tangerine --refresh
```

Options:

- `--refresh`: overwrite `app_theme.dart` even when it was edited.
- `--json`: print machine-readable output.

`app_theme.dart` is user-owned: without `--refresh` a locally modified file is reported as drift (`theme_drift`, exit `80`) and left untouched. `theme apply` validates the preset against `themes.schema.json` (schemaVersion 2) and writes the values-only theme file.

## `sync`

Re-applies the installed closure and the locked theme.

```bash
flutter_shadcn sync
```

Use `sync` after manually editing config or install paths, or to re-materialize a partially deleted install.

## `project`

Project-scoped repair and cleanup.

```bash
flutter_shadcn project reset
flutter_shadcn project reset --undo
flutter_shadcn project refresh
```

- `project reset`: removes CLI-managed files with a 24-hour undo window.
- `project refresh`: re-applies the installed closure and the locked theme.

## `registries`

Lists configured and discoverable registries.

```bash
flutter_shadcn registries
flutter_shadcn registries --json
```

Options:

- `--json`: print machine-readable output.

## `default`

Shows or sets the default registry namespace and source mode.

```bash
flutter_shadcn default
flutter_shadcn default shadcn
flutter_shadcn default shadcn --local
flutter_shadcn default shadcn --remote
```

Options:

- `--local`: persist a local development registry.
- `--remote`: switch back to the published remote registry.

## `validate`

Validates the registry manifest against the v2 schema.

```bash
flutter_shadcn validate
flutter_shadcn validate --json
```

What it checks:

- `schemaVersion` is 2 and required top-level keys are present
- every `deps` reference resolves
- every declared file exists and has a `fileHashes` entry
- relative paths and ids match the schema

Options:

- `--json`: print machine-readable output.

## `audit`

Compares installed files against `shadcn.lock`.

```bash
flutter_shadcn audit
flutter_shadcn audit --json
```

Use this to find drift between installed files and the recorded hashes. User-owned files are reported but never treated as updatable.

Options:

- `--json`: print machine-readable output.

## `doctor`

Diagnoses the manifest, closure, layout and lock drift.

```bash
flutter_shadcn doctor
flutter_shadcn doctor --json
```

What it reports:

- whether the manifest loads and validates
- whether every installed component's closure is present
- whether the layer directories exist at the right depth
- whether each installed file's hash matches the lock
- whether `pubspec.yaml` has the required SDK dependencies

Exit codes: `0` clean, `1` drift/modified, `2` broken closure, `3` manifest invalid.

Options:

- `--json`: print machine-readable output.

## `reset`

Clears the global CLI-managed cache and home-directory state.

```bash
flutter_shadcn reset
```

## `feedback`

Submits feedback or issue reports.

```bash
flutter_shadcn feedback
flutter_shadcn feedback --type bug --title "Button issue" --body "Describe the issue"
```

Options:

- `--type`, `-t`: `bug`, `feature`, `docs`, `question`, or `other`.
- `--title`: issue title.
- `--body`: issue body.

Without options, the command runs interactively.

## `version`

Shows CLI version information.

```bash
flutter_shadcn version
flutter_shadcn version --check
```

Options:

- `--check`: check for available updates.

## `upgrade`

Upgrades the CLI from pub.dev.

```bash
flutter_shadcn upgrade
flutter_shadcn upgrade --force
```

Options:

- `--force`, `-f`: force upgrade even if the installed version appears current.

## `docs` (advanced)

Regenerates the command reference from the CLI metadata.

```bash
flutter_shadcn --advanced docs --generate
```

Options:

- `--generate`, `-g`: regenerate `doc/reference/commands`.
