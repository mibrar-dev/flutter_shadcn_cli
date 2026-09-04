# Flutter Shadcn CLI Testing And Usage Guide

This guide is written for people who are not working inside the CLI codebase. Send this file to anyone who needs to test the CLI or learn the basic workflow.

Use a disposable Flutter project while testing. Do not run remove or reset commands inside a real app unless you are sure you want to change it.

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
flutter create shadcn_cli_test_app
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
- `.shadcn/state.json` exists.
- `lib/ui/shadcn/shared/` exists.
- `pubspec.yaml` has CLI-managed dependencies.
- Shared app/theme/localization files are installed by default when the registry provides them.

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

- Button files are created under `lib/ui/shadcn/components/`.
- `.shadcn/components/button.json` exists.
- `shadcn.lock` exists or is updated.

Check project health:

```bash
flutter_shadcn doctor
flutter_shadcn audit
flutter_shadcn deps
flutter analyze
```

Expected result:

- `doctor` completes successfully.
- `audit` reports installed files are present.
- `deps` reports dependency state.
- `flutter analyze` finishes without errors.

## Test Init In Detail

Start from a clean app, then run:

```bash
flutter_shadcn init --yes
```

Check the files created by init:

```bash
find .shadcn -maxdepth 4 -type f | sort
find lib/ui/shadcn/shared -maxdepth 5 -type f | sort
```

The important files/folders are:

```text
.shadcn/config.json
.shadcn/state.json
lib/ui/shadcn/shared/
```

If the official registry is being tested, also check that shared app/theme/localization files exist:

```bash
find lib/ui/shadcn/shared -type f | grep -E "app_theme|localizations"
```

Expected result: the command prints files such as:

```text
lib/ui/shadcn/shared/theme/app_theme.dart
lib/ui/shadcn/shared/localizations/shadcn_localizations.dart
lib/ui/shadcn/shared/localizations/shadcn_localizations_extensions.dart
```

Run init again:

```bash
flutter_shadcn init --yes
```

Expected result:

- It should not corrupt `.shadcn/config.json`.
- It should not duplicate dependencies in `pubspec.yaml`.
- It should not delete installed shared files.

## Test Every Main Command

Run this command checklist from the test app.

### Help And Version

```bash
flutter_shadcn --help
flutter_shadcn version
flutter_shadcn init --help
flutter_shadcn add --help
flutter_shadcn remove --help
flutter_shadcn dry-run --help
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
flutter_shadcn info @shadcn/button
```

Expected result:

- `registries` shows available registries.
- `list` shows available components.
- `search button` includes `button`.
- `info button` shows component details and install/import information.

### Dry Run

```bash
flutter_shadcn dry-run button
flutter_shadcn dry-run --all
```

Expected result:

- No component files are written by `dry-run`.
- `dry-run button` shows files/dependencies that would be installed.
- `dry-run --all` includes real registry components only.

### Add Components

Install a small set first:

```bash
flutter_shadcn add button
flutter_shadcn add card alert
```

Check generated files:

```bash
find lib/ui/shadcn/components -maxdepth 5 -type f | sort
find .shadcn/components -type f | sort
```

Expected result:

- Component Dart files exist.
- Component manifest files exist under `.shadcn/components/`.
- Existing files are not duplicated if you run the same `add` again.

Install all components when doing a full QA pass:

```bash
flutter_shadcn add --all
flutter_shadcn audit
flutter_shadcn deps
flutter analyze
```

Expected result:

- All components install successfully.
- `audit` succeeds.
- `deps` succeeds.
- `flutter analyze` succeeds.

### Remove Components

```bash
flutter_shadcn remove button
flutter_shadcn audit
flutter_shadcn add button
flutter_shadcn audit
```

Expected result:

- `remove button` removes the button files recorded by the button manifest.
- `audit` should still work.
- Re-adding `button` should restore it.

### Locale

```bash
flutter_shadcn locale init
```

Expected result:

- `l10n.yaml` is created.
- `lib/l10n/app_en.arb` is created.

Run it a second time:

```bash
flutter_shadcn locale init
```

Expected result: it should fail cleanly or explain that localization files already exist. It should not overwrite existing app translations.

### Assets

```bash
flutter_shadcn assets --list
flutter_shadcn assets --typography
flutter_shadcn assets --icons
```

Expected result:

- `--list` shows available asset groups.
- `--typography` installs font assets if the registry provides them.
- `--icons` installs icon assets if the registry provides them.
- `pubspec.yaml` is updated when assets are installed.

### Theme

```bash
flutter_shadcn theme --list
flutter_shadcn theme --apply amber-minimal
```

Expected result:

- Theme list loads.
- Applying a theme writes the registry-declared theme files.
- `.shadcn/config.json` records the selected theme.

### Platform And Sync

```bash
flutter_shadcn platform --list
flutter_shadcn sync
```

Expected result:

- `platform --list` prints platform target paths.
- `sync` completes without deleting installed components.

## Test Error Cases

These commands should fail in a clear way.

Missing component:

```bash
flutter_shadcn add component_that_does_not_exist
```

Expected result: the CLI says the component was not found.

Missing registry path:

```bash
flutter_shadcn --advanced list --registry-path /tmp/does-not-exist
```

Expected result: the CLI says the local registry was not found.

Diagnostics before components are installed:

```bash
flutter_shadcn deps --json
```

Expected result: it may report missing dependencies before components are installed, but it should not crash.

## Test With A Local Registry Checkout

Use this when testing changes before publishing the registry.

Set the registry path:

```bash
REGISTRY_ROOT=/absolute/path/to/shadcn_flutter_kit/flutter_shadcn_kit/lib/registry
QA_ROOT=$(mktemp -d /tmp/flutter_shadcn_manual.XXXXXX)
mkdir -p "$QA_ROOT/source_overlay"
ln -s "$REGISTRY_ROOT" "$QA_ROOT/source_overlay/registry"
ln -s "$REGISTRY_ROOT/shared" "$QA_ROOT/source_overlay/shared"
ln -s "$REGISTRY_ROOT/manifests" "$QA_ROOT/source_overlay/manifests"
```

Run CLI commands like this:

```bash
flutter_shadcn --advanced init --yes \
  --registry-path "$QA_ROOT/source_overlay/registry" \
  --skip-integrity

flutter_shadcn --advanced add button \
  --registry-path "$QA_ROOT/source_overlay/registry" \
  --skip-integrity
```

The overlay lets the CLI read registry manifests from `registry/` and inline init files from `shared/`.

## What To Record While Testing

For each failed command, record:

- The command you ran.
- The full output.
- The exit code if available.
- The files that changed.
- Whether this was a published registry or local registry test.

Useful evidence commands:

```bash
find .shadcn -maxdepth 5 -type f | sort
find lib/ui/shadcn -type f | sort
cat pubspec.yaml
flutter_shadcn doctor --json
flutter_shadcn audit --json
flutter_shadcn deps --json
flutter analyze
```

## Pass Checklist

Use this checklist for a release test:

- [ ] `flutter_shadcn version` works.
- [ ] `flutter_shadcn --help` works.
- [ ] `flutter_shadcn init --yes` creates `.shadcn` config/state.
- [ ] Init installs shared app/theme/localization files when provided by the registry.
- [ ] `list`, `search`, `info`, and `dry-run` work.
- [ ] `add button` installs files and manifest.
- [ ] `add --all` installs all registry components.
- [ ] `doctor` passes after install.
- [ ] `audit` passes after install.
- [ ] `deps` passes after install.
- [ ] `flutter analyze` passes after install.
- [ ] `remove button` and re-add works.
- [ ] `locale init` creates localization files.
- [ ] Asset commands behave clearly.
- [ ] Theme commands behave clearly.
- [ ] Missing component errors are clear.
- [ ] Missing local registry errors are clear.

