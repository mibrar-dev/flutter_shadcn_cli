# Complete User Guide

This is the A-Z guide for installing and using `flutter_shadcn`. The CLI installs Flutter UI components from a registry into your app, records what it installed in `shadcn.lock`, and gives you commands for discovery, theming, diagnostics and project recovery.

Quick path:

```bash
dart pub global activate flutter_shadcn_cli
flutter_shadcn init --yes
flutter_shadcn add button dialog input select calendar
flutter analyze
flutter build web
```

## 1. Requirements

You need:

- Flutter installed and available on `PATH`
- Dart installed through Flutter or the Dart SDK
- A Flutter project created with `flutter create` or an existing Flutter app
- Network access for the first remote registry fetch

Check your environment:

```bash
flutter --version
dart --version
```

## 2. Install the CLI

Install from pub.dev:

```bash
dart pub global activate flutter_shadcn_cli
```

Confirm the executable is available:

```bash
flutter_shadcn version
flutter_shadcn --help
```

The package also exposes a short `shadcn` alias. If the command is not found, add the Dart pub cache bin directory to your shell path:

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
```

For zsh, put that line in `~/.zshrc`. For bash, put it in `~/.bashrc` or `~/.bash_profile`, then restart the terminal.

## 3. Initialize a Flutter Project

Run `init` from your Flutter project root:

```bash
flutter create --empty my_app
cd my_app
flutter_shadcn init --yes
```

What `init` does:

- copies every `foundation/` and `theme/` unit (no component)
- writes `.shadcn/config.json` and `shadcn.lock` (lockfileVersion 2)
- generates `<installRoot>/theme/app_theme.dart` from a preset
- writes `<installRoot>/analysis_options.yaml` so the vendored tree stays out of the host app's lint rules

Choose a preset or install root:

```bash
flutter_shadcn init --theme claude --yes
flutter_shadcn init --dir lib/shadcn --yes
```

## 4. Add Components

Install one component:

```bash
flutter_shadcn add button
```

Install multiple components:

```bash
flutter_shadcn add button dialog input select calendar
```

An `@namespace/` prefix is accepted and stripped:

```bash
flutter_shadcn add @shadcn/button
```

Install every component from the selected registry:

```bash
flutter_shadcn add --all
```

Include preview files for a component:

```bash
flutter_shadcn add button --include-preview
```

## 5. Use Installed Components

After install, run:

```bash
flutter pub get
flutter analyze
```

Import the component from your install root. The default install root is `lib/ui/shadcn`:

```dart
import 'package:my_app/ui/shadcn/components/button/button.dart';
```

The exact import path depends on your app package name and the configured install root.

## 6. Discover Components

```bash
flutter_shadcn list
flutter_shadcn search toast
flutter_shadcn info gooey_toast
```

Use JSON output for scripts:

```bash
flutter_shadcn list --json
flutter_shadcn search button --json
flutter_shadcn info button --json
```

## 7. Preview Changes Before Writing

```bash
flutter_shadcn dry-run button dialog
flutter_shadcn dry-run --all
flutter_shadcn dry-run button dialog --json
```

`dry-run` reports the files, layer units and missing packages an install would involve.

## 8. Update Components

```bash
flutter_shadcn update --check
flutter_shadcn update button
flutter_shadcn update
```

`update` overwrites files whose bytes still match `shadcn.lock`, installs files the manifest has added, adds new pub packages, and reports locally modified files without touching them.

## 9. Remove Components

```bash
flutter_shadcn remove button
flutter_shadcn remove button badge
flutter_shadcn remove --all
flutter_shadcn remove button --force
```

Without `--force`, the CLI protects a component another installed component still depends on. User-owned `<name>_theme.dart` files are kept unless you pass `--purge-user-themes`.

## 10. Themes

```bash
flutter_shadcn theme list
flutter_shadcn theme apply amber-minimal
flutter_shadcn theme apply amber-minimal --refresh
```

`app_theme.dart` is user-owned. Without `--refresh`, an edited file is reported as drift (`theme_drift`, exit `80`) and left untouched.

## 11. Registries

```bash
flutter_shadcn registries
flutter_shadcn registries --json
flutter_shadcn default
flutter_shadcn default shadcn
```

Point the CLI at a local checkout or a hosted registry:

```bash
flutter_shadcn --registry /absolute/path/to/registry list
flutter_shadcn --registry https://example.com/registry add button
```

A remote registry is cached under `.shadcn/cache/registry`; `--offline` reads the cache only.

## 12. Sync Project State

Use `sync` after editing config or install paths, or to re-materialize a partially deleted install:

```bash
flutter_shadcn sync
```

## 13. Diagnostics

Run these before release:

```bash
flutter_shadcn validate
flutter_shadcn audit
flutter_shadcn doctor
flutter analyze
flutter test
flutter build web
```

What each diagnostic command does:

- `validate`: checks the registry manifest against the v2 schema and referenced files
- `audit`: compares installed files with the hashes in `shadcn.lock`
- `doctor`: reports the registry, install layout, closure gaps, lock drift and pubspec state

Machine-readable diagnostics:

```bash
flutter_shadcn validate --json
flutter_shadcn audit --json
flutter_shadcn doctor --json
flutter_shadcn update --check --json
```

## 14. Project Recovery

```bash
flutter_shadcn project reset
flutter_shadcn project reset --undo
flutter_shadcn project refresh
```

Typical use:

- `project reset`: snapshot and remove CLI-managed project artifacts
- `project reset --undo`: restore the latest non-expired reset snapshot
- `project refresh`: repair missing managed files without overwriting installed components

Global reset clears CLI-managed home-directory state:

```bash
flutter_shadcn reset
```

Use global reset when the cache or CLI home state is corrupted, not as a normal project cleanup command.

## 15. Tooling Commands

```bash
flutter_shadcn version
flutter_shadcn version --check
flutter_shadcn upgrade
flutter_shadcn upgrade --force
flutter_shadcn feedback
```

Advanced docs maintenance:

```bash
flutter_shadcn --advanced docs --generate
```

## 16. Global Flags

Global flags are passed before the command:

```bash
flutter_shadcn --verbose add button
flutter_shadcn --offline list
flutter_shadcn --registry ../registry add button
flutter_shadcn --advanced --help
```

Flags:

- `--verbose`: print extra logs
- `--offline`: disable network calls and use the cache only
- `--registry <path|url>`: override the registry source
- `--registry-name <namespace>`: select the active namespace
- `--advanced`: enable developer commands and options

## 17. Recommended Production Workflow

```bash
dart pub global activate flutter_shadcn_cli
flutter_shadcn version

flutter create --empty my_app
cd my_app

flutter_shadcn init --yes
flutter_shadcn registries
flutter_shadcn list

flutter_shadcn dry-run button dialog input select calendar
flutter_shadcn add button dialog input select calendar

flutter pub get
flutter_shadcn doctor
flutter_shadcn validate
flutter_shadcn audit
flutter_shadcn update --check

flutter analyze
flutter test
flutter build web
```

Commit these files:

- `.shadcn/config.json`
- `shadcn.lock`
- Generated files under your install root, usually `lib/ui/shadcn/`
- `pubspec.yaml` and `pubspec.lock`

## 18. Troubleshooting

### Command not found

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
```

Then reopen the terminal.

### Registry fetch fails

```bash
flutter_shadcn registries
flutter_shadcn doctor
flutter_shadcn --verbose list
```

Use `--offline` only after the registry has been cached.

### Analyzer fails after install

```bash
flutter pub get
flutter_shadcn doctor
flutter_shadcn audit
flutter analyze
```

The CLI writes `<installRoot>/analysis_options.yaml` so vendored registry code does not pollute the host app's lint rules.

### You need to undo CLI-managed files

```bash
flutter_shadcn project reset
flutter_shadcn project reset --undo
```

`project reset` creates a snapshot first; `project reset --undo` restores the latest non-expired snapshot.

## 19. Command Index

| Command | Purpose |
| --- | --- |
| `init` | Install the layer core and generate the app theme. |
| `add` | Install components and their closure. |
| `remove`, `rm` | Remove installed components and orphaned layer files. |
| `update` | Update installed components from the registry. |
| `dry-run` | Preview installs without writes. |
| `list`, `ls` | List available components. |
| `search` | Search the registry catalog. |
| `info`, `i` | Show a component's closure, files and API. |
| `theme` | List and apply theme presets. |
| `registries` | List configured/discovered registries. |
| `default` | Show or set the default namespace. |
| `sync` | Re-apply the installed closure and locked theme. |
| `project` | Repair or reset CLI-managed project files. |
| `doctor` | Diagnose the manifest, closure, layout and lock drift. |
| `validate` | Validate the registry manifest against the v2 schema. |
| `audit` | Compare installed files against `shadcn.lock`. |
| `reset` | Clear global CLI-managed state. |
| `feedback` | Submit guided feedback or issue reports. |
| `version` | Show the CLI version. |
| `upgrade` | Upgrade the CLI. |
| `docs` | Advanced generated command reference maintenance. |
