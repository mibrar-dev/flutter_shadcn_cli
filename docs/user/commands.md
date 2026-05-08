# Commands

This page explains every public command in `flutter_shadcn`. Examples use the current multi-registry CLI and canonical `@namespace/component` component addresses.

## Global Options

Global options appear before the command.

```bash
flutter_shadcn --verbose add button
flutter_shadcn --offline list
flutter_shadcn --registry-name shadcn validate
```

Options:

- `--verbose`, `-v`: print more detail while commands run.
- `--offline`: disable network calls and use cached or local registry data.
- `--registry-name <namespace>`: select the active registry namespace for commands that operate on one registry.
- `--help`, `-h`: show help.

## `init`

Initializes a Flutter project for a registry namespace.

```bash
flutter_shadcn init --yes
flutter_shadcn init shadcn --yes
```

What it does:

- creates or updates `.shadcn/config.json`
- creates or updates `.shadcn/state.json`
- runs inline registry bootstrap actions
- may copy shared files, create directories, update `pubspec.yaml`, and apply required theme scaffolding

Options:

- `--yes`, `-y`: run non-interactively and accept defaults.

Use `init shadcn` when you want a specific namespace. Without a namespace, the current default namespace is used. Non-interactive `init --yes` runs required bootstrap actions only; optional fonts, icons, and assets are installed separately with `assets`.

## `add`

Installs one or more components.

```bash
flutter_shadcn add button
flutter_shadcn add @shadcn/button
flutter_shadcn add button dialog accordion
```

What it does:

- resolves the component in enabled registries
- installs component files and shared files
- updates managed dependencies
- writes component manifests
- regenerates aliases when configured

Options:

- `--include-files <kind>`: install only selected optional file kinds.
- `--exclude-files <kind>`: skip selected optional file kinds.
- `--all`, `-a`: install all registry components.

Valid file kinds are `readme`, `preview`, and `meta`.

## `remove`

Removes installed components.

```bash
flutter_shadcn remove button
flutter_shadcn remove @shadcn/button --force
flutter_shadcn remove --all
```

What it does:

- deletes files recorded in component manifests
- updates install state
- removes managed dependency entries when possible
- regenerates aliases

Options:

- `--force`, `-f`: remove even when dependencies remain.
- `--all`, `-a`: remove all installed components.

Use `--force` carefully. Without it, the CLI protects components that are still required by other installed components.

## `dry-run`

Shows what an install would do without writing files.

```bash
flutter_shadcn dry-run button
flutter_shadcn dry-run button dialog --json
flutter_shadcn dry-run --all
```

What it reports:

- component files
- shared files
- dependencies
- assets
- fonts
- missing components

Options:

- `--all`, `-a`: include every registry component.
- `--json`: print machine-readable output.

## `list`

Lists available components in a registry.

```bash
flutter_shadcn list
flutter_shadcn list @shadcn
flutter_shadcn list --refresh
flutter_shadcn list --json
```

Options:

- `--refresh`: refresh cached registry data from remote.
- `--json`: print machine-readable output.

Use `list @namespace` to browse a specific registry namespace.

## `search`

Searches registry components by name, description, or tags.

```bash
flutter_shadcn search button
flutter_shadcn search @shadcn button
flutter_shadcn search @shadcn --json
```

Options:

- `--refresh`: refresh cached registry data from remote.
- `--json`: print machine-readable output.

If you pass a namespace without a query, `search` behaves like `list` for that namespace.

## `info`

Shows detailed information for one component.

```bash
flutter_shadcn info button
flutter_shadcn info @shadcn/button
flutter_shadcn info @shadcn/button --json
```

Options:

- `--refresh`: refresh cached registry data from remote.
- `--json`: print machine-readable output.

Use `@namespace/component` when the component name may exist in multiple registries.

## `sync`

Synchronizes project files from `.shadcn/config.json`.

```bash
flutter_shadcn sync
```

Use `sync` after manually editing config, install paths, aliases, or platform target settings.

## `assets`

Installs registry-defined assets through inline registry actions.

```bash
flutter_shadcn assets --typography
flutter_shadcn assets --icons
flutter_shadcn assets --all
flutter_shadcn assets --list
```

Options:

- `--icons`: install icon font assets.
- `--typography`: install typography font assets.
- `--fonts`: alias for `--typography`.
- `--all`, `-a`: install icon and typography assets.
- `--list`: show that assets are provided by inline registry actions.

Assets are not installed through old component fallback IDs. The selected registry must provide matching inline actions.

## `locale`

Creates local Flutter localization files used by component locale resources.

```bash
flutter_shadcn locale init
```

What it does:

- creates `l10n.yaml`
- creates `lib/l10n/`
- creates `lib/l10n/app_en.arb`

Component installs merge registry-provided, component-local locale resources into the app ARB file without overwriting existing app keys. A component can publish its own JSON or ARB locale file, and only installed components contribute entries. Component removal only removes locale keys that were added by that component and are not owned by another installed component.

## `theme`

Lists or applies registry theme presets.

```bash
flutter_shadcn theme --list
flutter_shadcn theme --apply modern-minimal
flutter_shadcn theme modern-minimal
```

Options:

- `--list`: list available presets.
- `--refresh`: refresh theme cache.
- `--apply`, `-a <id>`: apply a preset by ID.

Each registry owns its theme format and generation pipeline. Conversion should happen at registry publish time. The CLI consumes only pre-generated, hash-verified theme artifacts.

If no theme action is provided, the CLI opens the interactive theme chooser.

## `theme widget`

Lists or resets widget-level theme overrides when the selected registry publishes widget theme artifacts.

```bash
flutter_shadcn theme widget --list
flutter_shadcn theme widget button --list-targets
flutter_shadcn theme widget button --reset
```

Options:

- `--list`: list themeable widgets.
- `--list-targets`: list theme targets for one widget.
- `--reset`: remove widget theme overrides.

Widget theme application from manifests is not part of the default public workflow. Advanced `--apply-file` and `--apply-url` inputs are experimental manifest flows, and they are only available when the registry publishes compatible widget artifacts.

## `registries`

Lists configured and discoverable registries.

```bash
flutter_shadcn registries
flutter_shadcn registries --json
```

The output shows namespace, source, enabled status, default marker, registry path or base URL, and capabilities.

Options:

- `--json`: print machine-readable output.

## `default`

Shows or sets the default registry namespace and source mode.

```bash
flutter_shadcn default
flutter_shadcn default shadcn
flutter_shadcn --advanced default shadcn --local
flutter_shadcn --advanced default shadcn --remote
```

The default namespace is used when a component name is unqualified and not ambiguous.

## `platform`

Lists or overrides platform target paths.

```bash
flutter_shadcn platform --list
flutter_shadcn platform --set ios.infoPlist=ios/Runner/Info.plist
flutter_shadcn platform --reset ios.infoPlist
```

Options:

- `--list`: list platform targets.
- `--set <platform.section=path>`: set an override. Repeatable.
- `--reset <platform.section>`: remove an override. Repeatable.

Platform targets are stored in `.shadcn/config.json`.

## `validate`

Validates the selected registry.

```bash
flutter_shadcn validate
flutter_shadcn validate --json
flutter_shadcn --registry-name shadcn validate
```

What it checks:

- `components.json`
- registry file dependencies
- referenced files
- schema validation

Options:

- `--json`: print machine-readable output.

## `audit`

Audits installed components against registry metadata.

```bash
flutter_shadcn audit
flutter_shadcn audit --json
```

Use this to find drift between installed component manifests and the current registry.

Options:

- `--json`: print machine-readable output.

## `deps`

Compares registry dependency requirements with your `pubspec.yaml`.

```bash
flutter_shadcn deps
flutter_shadcn deps --all
flutter_shadcn deps --json
```

Options:

- `--all`, `-a`: compare dependencies for all registry components.
- `--json`: print machine-readable output.

## `doctor`

Prints diagnostic information for the current project and registry.

```bash
flutter_shadcn doctor
flutter_shadcn doctor --json
```

What it reports:

- CLI and working directory
- registry mode and resolved root
- config values
- install paths
- schema validation status
- platform targets

Options:

- `--json`: print machine-readable output.

## `feedback`

Submits feedback or issue reports.

```bash
flutter_shadcn feedback
flutter_shadcn feedback @shadcn
flutter_shadcn feedback --type bug --title "Button issue" --body "Describe the issue"
```

Options:

- `--type`, `-t`: `bug`, `feature`, `docs`, `question`, `performance`, or `other`.
- `--title`: issue title.
- `--body`: issue body.
- `@namespace`: optional registry context.

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
