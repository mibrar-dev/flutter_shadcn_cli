# Flutter Shadcn CLI Testing And Usage Guide

This guide is written for people who are not working inside the CLI codebase. Send this file to anyone who needs to test the CLI or learn the basic workflow.

Use a disposable Flutter project while testing. Do not run `remove` or `reset` commands inside a real app unless you are sure you want to change it.

## What You Need

Install these first:

```bash
flutter --version
dart --version
```

Install the CLI:

```bash
dart pub global activate flutter_shadcn_cli
flutter_shadcn version
```

If `flutter_shadcn` is not found, add the Dart pub cache bin folder to your shell path:

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
```

## Create A Test App

Create a fresh app for testing:

```bash
flutter create --empty shadcn_cli_test_app
cd shadcn_cli_test_app
flutter pub get
```

All commands below should be run from inside this app folder.

## Quick Use Flow

Run the CLI setup:

```bash
flutter_shadcn init --yes
```

Expected result:

- `.shadcn/config.json` exists.
- `shadcn.lock` exists (`lockfileVersion: 2`).
- `lib/ui/shadcn/foundation/` and `lib/ui/shadcn/theme/` exist.
- `lib/ui/shadcn/theme/app_theme.dart` exists.

List components:

```bash
flutter_shadcn list
```

Search for a component:

```bash
flutter_shadcn search button
```

Preview an install without writing files:

```bash
flutter_shadcn dry-run button
```

Install a component:

```bash
flutter_shadcn add button
```

Expected result:

- Button files are created under `lib/ui/shadcn/components/button/`.
- The layer closure (primitives, foundation, theme) is present.
- `shadcn.lock` records the component and its files.

Check project health:

```bash
flutter_shadcn doctor
flutter_shadcn audit
flutter_shadcn update --check
flutter analyze
```

Expected result:

- `doctor` completes with exit `0`.
- `audit` reports installed files are present.
- `update --check` reports nothing to do.
- `flutter analyze` finishes with `No issues found!`.

## Test Init In Detail

Start from a clean app, then run:

```bash
flutter_shadcn init --yes
```

Check the files created by init:

```bash
find .shadcn -maxdepth 4 -type f | sort
find lib/ui/shadcn/foundation lib/ui/shadcn/theme -type f | sort
```

The important files/folders are:

```text
.shadcn/config.json
shadcn.lock
lib/ui/shadcn/foundation/
lib/ui/shadcn/theme/
```

Run init again:

```bash
flutter_shadcn init --yes
```

Expected result:

- It should not corrupt `.shadcn/config.json`.
- It should not duplicate dependencies in `pubspec.yaml`.
- It should not delete installed files.

## Test Every Main Command

Run this command checklist from the test app.

### Help And Version

```bash
flutter_shadcn --help
flutter_shadcn version
flutter_shadcn init --help
flutter_shadcn add --help
flutter_shadcn remove --help
flutter_shadcn update --help
flutter_shadcn doctor --help
```

Expected result: every command prints help or version text and exits cleanly.

### Registry Discovery

```bash
flutter_shadcn registries
flutter_shadcn default
flutter_shadcn list
flutter_shadcn search button
flutter_shadcn info button
```

Expected result:

- `registries` shows the configured registry source.
- `list` shows available components.
- `search button` includes `button`.
- `info button` shows the closure, files and import path.

### Dry Run

```bash
flutter_shadcn dry-run button
flutter_shadcn dry-run --all
```

Expected result:

- No component files are written by `dry-run`.
- `dry-run button` shows the files and packages that would be installed.

### Add Components

Install a small set first:

```bash
flutter_shadcn add button
flutter_shadcn add dialog input select calendar
```

Check generated files:

```bash
find lib/ui/shadcn/components -maxdepth 5 -type f | sort
```

Expected result:

- Component Dart files exist.
- Existing files are not duplicated if you run the same `add` again.

Install all components when doing a full QA pass:

```bash
flutter_shadcn add --all
flutter_shadcn audit
flutter_shadcn update --check
flutter analyze
```

Expected result:

- All components install successfully.
- `audit` succeeds.
- `update --check` reports nothing to do.
- `flutter analyze` succeeds.

### Update Components

```bash
flutter_shadcn update --check
flutter_shadcn update
```

Expected result:

- `--check` reports whether anything is behind or modified and exits `1` when it is.
- `update` overwrites files whose bytes still match `shadcn.lock` and leaves locally modified files alone.

### Remove Components

```bash
flutter_shadcn remove button
flutter_shadcn audit
flutter_shadcn add button
flutter_shadcn audit
```

Expected result:

- `remove button` removes the registry-owned button files and keeps `button_theme.dart`.
- `audit` should still work.
- Re-adding `button` should restore it.

### Theme

```bash
flutter_shadcn theme list
flutter_shadcn theme apply amber-minimal
flutter_shadcn theme apply amber-minimal --refresh
```

Expected result:

- Theme list loads.
- Applying a theme writes `<installRoot>/theme/app_theme.dart`.
- `.shadcn/config.json` and `shadcn.lock` record the selected theme.
- Without `--refresh`, an edited `app_theme.dart` is reported as drift (`theme_drift`, exit `80`).

### Sync

```bash
flutter_shadcn sync
```

Expected result: `sync` re-applies the installed closure and the locked theme without deleting installed components.

## Test Error Cases

These commands should fail in a clear way.

Missing component:

```bash
flutter_shadcn add component_that_does_not_exist
```

Expected result: the CLI exits `30` and says the component was not found.

Missing registry path:

```bash
flutter_shadcn --registry /tmp/does-not-exist list
```

Expected result: the CLI exits `10` and says the local registry was not found.

## Test With A Local Registry Checkout

Use this when testing changes before publishing the registry.

```bash
REGISTRY_ROOT=/absolute/path/to/shadcn_flutter_kit/flutter_shadcn_kit/lib/registry
flutter_shadcn --registry "$REGISTRY_ROOT" init --yes
flutter_shadcn --registry "$REGISTRY_ROOT" add button
flutter_shadcn --registry "$REGISTRY_ROOT" doctor
```

The `--registry` override points the CLI at the checkout instead of the remote registry.

## What To Record While Testing

For each failed command, record:

- The command you ran.
- The full output.
- The exit code if available.
- The files that changed.
- Whether this was a published registry or a local registry test.

Useful evidence commands:

```bash
find .shadcn -maxdepth 5 -type f | sort
find lib/ui/shadcn -type f | sort
cat pubspec.yaml
flutter_shadcn doctor --json
flutter_shadcn audit --json
flutter_shadcn update --check --json
flutter analyze
```

## Pass Checklist

Use this checklist for a release test:

- [ ] `flutter_shadcn version` works.
- [ ] `flutter_shadcn --help` works.
- [ ] `flutter_shadcn init --yes` creates `.shadcn/config.json`, `shadcn.lock` and the theme.
- [ ] `list`, `search`, `info`, and `dry-run` work.
- [ ] `add button` installs files and updates the lock.
- [ ] `add --all` installs all registry components.
- [ ] `doctor` passes after install.
- [ ] `audit` passes after install.
- [ ] `update --check` reports nothing to do after a fresh install.
- [ ] `flutter analyze` passes after install.
- [ ] `remove button` and re-add works, keeping `button_theme.dart`.
- [ ] Theme commands behave clearly.
- [ ] Missing component errors are clear.
- [ ] Missing local registry errors are clear.
