# CLI Manual QA Guide

This guide is for manually testing the whole `flutter_shadcn` CLI in a real Flutter app. It is not a user tutorial. Treat it as a QA map: every command family gets a pass, every pass has expected evidence, and failures should be recorded with the command, exit code, and project diff.

Use a disposable Flutter app for every run. Never run destructive commands such as `project reset` against an app you care about.

## Automated Smoke

Run this first. It creates a temporary Flutter app, initializes the CLI against a local copy of the real registry, installs representative components, runs `flutter pub get`, checks generated files, runs the diagnostics, and reports `flutter analyze`.

```bash
tool/cli_manual_smoke.sh \
  --registry-root /absolute/path/to/shadcn_flutter_kit/flutter_shadcn_kit/lib/registry \
  --keep
```

Use strict analyzer mode to treat analyzer output as a smoke failure:

```bash
tool/cli_manual_smoke.sh \
  --registry-root /absolute/path/to/shadcn_flutter_kit/flutter_shadcn_kit/lib/registry \
  --strict-analyze
```

The package test suite also carries the tagged e2e acceptance test, which runs the same flow through the CLI binary:

```bash
dart test -t e2e --run-skipped
```

## Manual Run Setup

Create a clean app:

```bash
flutter create --empty shadcn_cli_manual_test
cd shadcn_cli_manual_test
flutter pub get
```

Pick the registry source before testing.

| Mode | Use When | Command Shape |
| --- | --- | --- |
| Published registry | Test the public default registry path | `flutter_shadcn init --yes` |
| Local real registry | Test a local `shadcn_flutter_kit` checkout | `flutter_shadcn --registry <registry> ...` |

## Pass 1: CLI Starts

```bash
flutter_shadcn version
flutter_shadcn --help
flutter_shadcn init --help
flutter_shadcn add --help
```

Expected: version and help print without crashing, and every documented command resolves with `--help`.

## Pass 2: Init

```bash
flutter_shadcn --registry "$REGISTRY_ROOT" init --yes
```

Expected:

- `.shadcn/config.json` exists.
- `shadcn.lock` exists with `lockfileVersion: 2`.
- `lib/ui/shadcn/foundation/` and `lib/ui/shadcn/theme/` exist.
- `lib/ui/shadcn/theme/app_theme.dart` exists.
- Init can be repeated without corrupting config or duplicating dependencies.

## Pass 3: Discovery

```bash
flutter_shadcn --registry "$REGISTRY_ROOT" list
flutter_shadcn --registry "$REGISTRY_ROOT" search button
flutter_shadcn --registry "$REGISTRY_ROOT" info button
flutter_shadcn --registry "$REGISTRY_ROOT" dry-run button
```

Expected:

- `list` shows the registry component count.
- `search button` returns `button`.
- `info button` shows the closure and the computed import path.
- `dry-run button` prints planned files without creating component files.

JSON output should be valid and free of warning text on stdout.

## Pass 4: Component Install

```bash
flutter_shadcn --registry "$REGISTRY_ROOT" add button
flutter_shadcn --registry "$REGISTRY_ROOT" add dialog input select calendar
```

Expected:

- Component files exist under `lib/ui/shadcn/components/...`.
- The layer closure (primitives, foundation, theme) is present.
- `shadcn.lock` records the components and their files.
- Missing pub packages are added to `pubspec.yaml`.
- Re-running the same `add` command is idempotent.

Evidence commands:

```bash
find lib/ui/shadcn/components -maxdepth 5 -type f | sort | sed -n '1,120p'
cat shadcn.lock
flutter pub get
flutter analyze
```

## Pass 5: Update, Remove And Sync

```bash
flutter_shadcn --registry "$REGISTRY_ROOT" update --check
flutter_shadcn --registry "$REGISTRY_ROOT" remove dialog
flutter_shadcn --registry "$REGISTRY_ROOT" sync
flutter_shadcn --registry "$REGISTRY_ROOT" audit
```

Expected:

- `update --check` reports nothing to do after a fresh install.
- `remove dialog` removes only registry-owned files and keeps `dialog_theme.dart`.
- `sync` re-applies the installed closure and the locked theme.
- `audit` does not crash.

## Pass 6: Theme

```bash
flutter_shadcn --registry "$REGISTRY_ROOT" theme list
flutter_shadcn --registry "$REGISTRY_ROOT" theme apply amber-minimal
flutter_shadcn --registry "$REGISTRY_ROOT" theme apply amber-minimal --refresh
```

Expected:

- Theme list loads from the manifest `themes`.
- Apply writes only `<installRoot>/theme/app_theme.dart`.
- An edited `app_theme.dart` is refused as drift (`theme_drift`, exit `80`) without `--refresh`.
- `.shadcn/config.json` and `shadcn.lock` record the selected theme.

## Pass 7: Registries And Default

```bash
flutter_shadcn registries
flutter_shadcn default
flutter_shadcn default shadcn
```

Expected: `registries` lists the configured source, and `default` updates only `.shadcn/config.json`.

## Pass 8: Diagnostics And Recovery

```bash
flutter_shadcn doctor
flutter_shadcn validate
flutter_shadcn project refresh
flutter_shadcn project reset
flutter_shadcn project reset --undo
flutter_shadcn reset
```

Expected:

- `doctor` reports the registry, paths, closure, lock drift and pubspec state.
- `validate` reports manifest/source issues without mutating the project.
- `project refresh` repairs missing managed files.
- `project reset` snapshots managed files before deleting.
- `project reset --undo` restores within the undo window.
- Global `reset` does not delete project files.

## Pass 9: Negative Cases

Run these in a disposable app or fixture registry:

| Case | Command | Expected |
| --- | --- | --- |
| Bad registry path | `flutter_shadcn --registry /missing list` | Exit `10`, clear error |
| Invalid manifest | Fixture with `schemaVersion: 1` | Exit `20` schema error |
| Import escape | Fixture file importing outside the layout | Rejected before writes |
| Missing component | `flutter_shadcn add nope` | Exit `30` |
| Remove dependent | Install a dependent graph, remove a required base component | Refused unless `--force` |

## Triage Format

For every failure, record:

```text
Command:
Exit code:
Expected:
Actual:
Registry source:
Generated files changed:
Analyzer output:
Notes:
```

## Completion Criteria

A full manual pass is complete when:

- The smoke script and `dart test -t e2e --run-skipped` pass.
- Init, discovery, add, update, remove, theme, registry, diagnostics, and recovery command families were exercised.
- `flutter pub get` succeeds after install.
- `flutter analyze` output is either clean or every issue is classified.
- Any JSON command produces parseable JSON without warning text mixed into stdout.
