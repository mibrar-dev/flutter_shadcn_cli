# Complete User Guide

This is the A-Z guide for installing and using `flutter_shadcn`. The CLI installs Flutter UI components from a registry into your app, records what it installed under `.shadcn`, and gives you commands for discovery, theming, assets, diagnostics, and project recovery.

Quick path:

```bash
dart pub global activate flutter_shadcn_cli
flutter_shadcn init --yes
flutter_shadcn add button file_picker gooey_toast
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

The package also exposes a short `shadcn` alias when your shell can find Dart global executables.

If the command is not found, add the Dart pub cache bin directory to your shell path:

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
```

For zsh, put that line in `~/.zshrc`. For bash, put it in `~/.bashrc` or `~/.bash_profile`, then restart the terminal.

## 3. Initialize a Flutter Project

Run `init` from your Flutter project root:

```bash
flutter create my_app
cd my_app
flutter_shadcn init --yes
```

What `init` does:

- Creates or updates `.shadcn/config.json`
- Creates or updates `.shadcn/state.json`
- Runs registry bootstrap actions
- Copies shared primitives, theme files, localization helpers, and utility files
- Adds required dependencies to `pubspec.yaml`
- Applies the registry default theme when the registry provides one

Initialize a specific registry namespace:

```bash
flutter_shadcn init shadcn --yes
```

Use non-interactive init in CI or templates:

```bash
flutter_shadcn init --yes
```

## 4. Add Components

Install one component:

```bash
flutter_shadcn add button
```

Install multiple components:

```bash
flutter_shadcn add button dialog accordion
```

Install from a specific namespace:

```bash
flutter_shadcn add @shadcn/button
```

Use namespace-qualified addresses when:

- Multiple enabled registries expose the same component ID
- You want deterministic install behavior in scripts
- You are testing a registry before release

Install all components from the selected registry:

```bash
flutter_shadcn add --all
```

Control optional files:

```bash
flutter_shadcn add button --exclude-files readme,preview,meta
flutter_shadcn add button --include-files preview
```

Valid optional file kinds are `readme`, `preview`, and `meta`.

## 5. Use Installed Components

After install, run:

```bash
flutter pub get
flutter analyze
```

Import generated component files from your app install root. The default install root is `lib/ui/shadcn`.

Example:

```dart
import 'package:my_app/ui/shadcn/components/control/button/button.dart';
```

The exact import path depends on your app package name and configured install root.

## 6. Discover Components

List the active registry catalog:

```bash
flutter_shadcn list
```

Search by name, description, or tag:

```bash
flutter_shadcn search toast
```

Show details for one component:

```bash
flutter_shadcn info gooey_toast
flutter_shadcn info @shadcn/file_picker
```

Refresh remote registry data:

```bash
flutter_shadcn list --refresh
flutter_shadcn info @shadcn/button --refresh
```

Use JSON output for scripts:

```bash
flutter_shadcn list --json
flutter_shadcn search button --json
flutter_shadcn info @shadcn/button --json
```

## 7. Preview Changes Before Writing

Use `dry-run` before broad installs:

```bash
flutter_shadcn dry-run button dialog
flutter_shadcn dry-run --all
flutter_shadcn dry-run button dialog --json
```

`dry-run` reports the files, shared files, dependencies, assets, fonts, and missing components that an install would involve.

## 8. Remove Components

Remove one component:

```bash
flutter_shadcn remove button
```

Remove several:

```bash
flutter_shadcn remove button badge
```

Remove every installed component:

```bash
flutter_shadcn remove --all
```

Force removal when another installed component still references the target:

```bash
flutter_shadcn remove button --force
```

Use `--force` carefully. Without it, the CLI protects dependency relationships.

## 9. Themes

List registry theme presets:

```bash
flutter_shadcn theme --list
```

Apply a preset:

```bash
flutter_shadcn theme --apply amber-minimal
```

Short form:

```bash
flutter_shadcn theme amber-minimal
```

Refresh theme metadata:

```bash
flutter_shadcn theme --list --refresh
```

Widget-level theme commands are available when the selected registry publishes compatible widget theme artifacts:

```bash
flutter_shadcn theme widget --list
flutter_shadcn theme widget button --list-targets
flutter_shadcn theme widget button --reset
```

## 10. Assets

Install registry-managed icon and typography assets:

```bash
flutter_shadcn assets --all
flutter_shadcn assets --icons
flutter_shadcn assets --fonts
```

List asset actions:

```bash
flutter_shadcn assets --list
```

Assets are installed through registry inline actions. They are not installed through old component fallback IDs.

## 11. Registries and Namespaces

Show available and configured registries:

```bash
flutter_shadcn registries
flutter_shadcn registries --json
```

Show the default namespace:

```bash
flutter_shadcn default
```

Set the default namespace:

```bash
flutter_shadcn default shadcn
```

Run a command against a namespace without changing the default:

```bash
flutter_shadcn --registry-name shadcn validate
flutter_shadcn list @shadcn
flutter_shadcn add @shadcn/button
```

Advanced local registry development:

```bash
flutter_shadcn --advanced --registry-path /absolute/path/to/registry list
flutter_shadcn --advanced --registries-path /absolute/path/to/registries.json registries
flutter_shadcn --advanced --registry-url https://example.com/registry list
```

Use advanced registry overrides only when authoring, debugging, or testing a registry.

## 12. Platform Targets

List configured platform targets:

```bash
flutter_shadcn platform --list
```

Set an override:

```bash
flutter_shadcn platform --set ios.infoPlist=ios/Runner/Info.plist
```

Reset an override:

```bash
flutter_shadcn platform --reset ios.infoPlist
```

Platform target overrides are stored in `.shadcn/config.json`.

## 13. Sync Project State

Use `sync` after editing `.shadcn/config.json`, changing install paths, or repairing generated aliases:

```bash
flutter_shadcn sync
```

## 14. Diagnostics and QA

Run these before release:

```bash
flutter_shadcn validate
flutter_shadcn audit
flutter_shadcn deps
flutter_shadcn doctor
flutter analyze
flutter test
flutter build web
```

What each diagnostic command does:

- `validate`: checks registry metadata, schemas, and referenced files
- `audit`: compares installed components with current registry metadata
- `deps`: compares registry dependency requirements with `pubspec.yaml`
- `doctor`: prints CLI, registry, config, schema, platform, and path diagnostics

Machine-readable diagnostics:

```bash
flutter_shadcn validate --json
flutter_shadcn audit --json
flutter_shadcn deps --json
flutter_shadcn doctor --json
```

## 15. Project Recovery

Project commands repair or reset CLI-managed files.

```bash
flutter_shadcn project reset
flutter_shadcn project undo
flutter_shadcn project refresh
```

Typical use:

- `project reset`: snapshot and remove CLI-managed project artifacts
- `project undo`: restore the latest non-expired reset snapshot
- `project refresh`: repair missing scaffold files without overwriting installed components

Global reset clears CLI-managed home-directory state:

```bash
flutter_shadcn reset
```

Use global reset when cache or CLI home state is corrupted, not as a normal project cleanup command.

## 16. Tooling Commands

Show version:

```bash
flutter_shadcn version
flutter_shadcn version --check
```

Upgrade:

```bash
flutter_shadcn upgrade
flutter_shadcn upgrade --force
```

Submit feedback:

```bash
flutter_shadcn feedback
flutter_shadcn feedback --type bug --title "Button issue" --body "Describe the issue"
```

Advanced docs and skill commands:

```bash
flutter_shadcn --advanced docs
flutter_shadcn --advanced install-skill flutter-shadcn-ui
```

## 17. Global Flags

Global flags are passed before the command:

```bash
flutter_shadcn --verbose add button
flutter_shadcn --offline list
flutter_shadcn --registry-name shadcn validate
flutter_shadcn --advanced --help
```

Flags:

- `--verbose`: print extra logs
- `--offline`: disable network calls and use cache only
- `--registry-name <namespace>`: select the active namespace
- `--advanced`: enable developer and experimental commands/options
- `--registry-path <path>`: advanced local registry root
- `--registry-url <url>`: advanced remote registry URL
- `--registries-path <path>`: advanced local registry directory file
- `--skip-integrity`: advanced integrity bypass for local development

## 18. Recommended Production Workflow

Use this sequence for a real app:

```bash
dart pub global activate flutter_shadcn_cli
flutter_shadcn version

flutter create my_app
cd my_app

flutter_shadcn init --yes
flutter_shadcn registries
flutter_shadcn list

flutter_shadcn dry-run button file_picker gooey_toast
flutter_shadcn add button file_picker gooey_toast

flutter pub get
flutter_shadcn doctor
flutter_shadcn validate
flutter_shadcn audit
flutter_shadcn deps

flutter analyze
flutter test
flutter build web
```

Commit these files:

- `.shadcn/config.json`
- `.shadcn/state.json`
- `.shadcn/components/`
- Generated files under your install root, usually `lib/ui/shadcn/`
- `pubspec.yaml` and `pubspec.lock`
- Any registry-managed assets copied into the app

## 19. Troubleshooting

### Command not found

Add pub global executables to PATH:

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
```

Then reopen the terminal.

### Component name is ambiguous

Use a namespace:

```bash
flutter_shadcn add @shadcn/button
```

Or select a namespace for the command:

```bash
flutter_shadcn --registry-name shadcn add button
```

### Registry fetch fails

Run:

```bash
flutter_shadcn registries
flutter_shadcn doctor
flutter_shadcn --verbose list
```

Use `--offline` only after the registry has been cached.

### Analyzer fails after install

Run:

```bash
flutter pub get
flutter_shadcn doctor
flutter_shadcn audit
flutter_shadcn deps
flutter analyze
```

If dependencies are missing, rerun the component install or inspect `pubspec.yaml`.

### You need to undo CLI-managed files

Run:

```bash
flutter_shadcn project reset
flutter_shadcn project undo
```

`project reset` creates a snapshot first. `project undo` restores the latest non-expired snapshot.

## 20. Command Index

| Command | Purpose |
| --- | --- |
| `init` | Initialize `.shadcn` config/state and bootstrap shared registry files. |
| `add` | Install components and dependencies. |
| `remove`, `rm` | Remove installed components. |
| `dry-run` | Preview installs without writes. |
| `list`, `ls` | List available components. |
| `search` | Search the registry catalog. |
| `info`, `i` | Show component details. |
| `registries` | List configured/discovered registries. |
| `default` | Show or set default namespace. |
| `sync` | Sync project files from config. |
| `project` | Repair, reset, undo, or refresh CLI-managed project files. |
| `assets` | Install registry-managed assets. |
| `theme` | List/apply theme presets and manage widget theme metadata. |
| `platform` | Configure platform target paths. |
| `doctor` | Print project and registry diagnostics. |
| `validate` | Validate registry integrity. |
| `audit` | Compare installed components with registry metadata. |
| `deps` | Compare registry dependencies with `pubspec.yaml`. |
| `reset` | Clear global CLI-managed state. |
| `feedback` | Submit guided feedback or issue reports. |
| `version` | Show CLI version. |
| `upgrade` | Upgrade the CLI. |
| `docs` | Advanced generated command reference maintenance. |
| `install-skill` | Advanced AI skill installation workflow. |

