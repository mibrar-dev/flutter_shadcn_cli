# Manual Testing Guide

Use this guide to validate `flutter_shadcn` in a real Flutter project, outside automated tests. It covers two modes:

- manual user testing in a local app
- AI-assisted testing where an agent runs the CLI and verifies project state

Run project commands from the Flutter app root unless a step says otherwise.

## 1. Prepare a Real Test App

Create a clean app:

```bash
flutter create shadcn_cli_manual_test
cd shadcn_cli_manual_test
flutter pub get
flutter_shadcn version
flutter_shadcn doctor
```

Expected:

- `flutter_shadcn version` prints the installed CLI version.
- `flutter_shadcn doctor` runs without crashing.
- `.shadcn/` does not exist yet.

If you are testing unpublished registry content, decide which registry source you will use before running `init`:

- published registry directory only
- local `registries.json` plus a local registry root

## 2. Test `init`

### Published registry path

```bash
flutter_shadcn init --yes
```

### Local registry development path

```bash
flutter_shadcn --advanced init shadcn \
  --registries-path /absolute/path/to/registries.json \
  --registry-path /absolute/path/to/local/registry \
  --skip-integrity \
  --yes
```

Expected:

- `.shadcn/config.json` is created.
- `.shadcn/state.json` is created.
- registry inline init actions run.
- shared scaffold files are installed under the configured shared path.
- `pubspec.yaml` is updated only when the registry declares package, asset, or font changes.

Minimum file checks after `init`:

```bash
ls .shadcn
find lib -path '*shadcn*' | sort
```

Check specifically for shared theme scaffolding:

```bash
find lib -path '*shadcn/shared/theme*' | sort
```

Expected:

- shared theme files declared by the registry exist
- if the registry exposes themes, the init flow offers or applies the current theme flow
- no legacy converter script is downloaded or executed

## 3. Verify Project Health After `init`

```bash
flutter pub get
flutter analyze
flutter_shadcn doctor
```

Expected:

- `flutter pub get` succeeds
- `flutter analyze` succeeds or reports only pre-existing app issues unrelated to CLI output
- `flutter_shadcn doctor` reports a healthy initialized project

If `doctor` reports missing shared files, compare the project against the registry entry and the selected init actions before testing more commands.

## 4. Test Discovery Commands

Run both plain and JSON output:

```bash
flutter_shadcn list
flutter_shadcn search button
flutter_shadcn info @shadcn/button

flutter_shadcn --json list
flutter_shadcn search --json button
flutter_shadcn info @shadcn/button --json
flutter_shadcn doctor --json
flutter_shadcn validate --json
```

Expected:

- discovery commands resolve through the registry directory entry, not a stale root `index.json`
- JSON output is valid whether `--json` appears before, after, or inside the command
- `info` returns the same component when addressed as `@namespace/component` or `namespace:component`

Also test explicit namespace selection:

```bash
flutter_shadcn list @shadcn
flutter_shadcn search @shadcn button
flutter_shadcn info shadcn:button
```

## 5. Test Component Install and Remove

```bash
flutter_shadcn dry-run @shadcn/button
flutter_shadcn add @shadcn/button
flutter_shadcn add @shadcn/card @shadcn/dialog
flutter_shadcn remove @shadcn/card
```

Expected:

- `dry-run` reports writes without changing files
- `add` writes component files, manifests, and dependency updates
- `.shadcn/components/` contains manifests for installed components
- `.shadcn/state.json` updates `managedDependencies`
- `remove` deletes files recorded in manifests and preserves shared files still required elsewhere

Collision check:

```bash
flutter_shadcn add button
```

Expected:

- succeeds only if `button` is unique across enabled registries
- otherwise fails and asks for a namespaced component address

## 6. Test Themes

List and apply themes:

```bash
flutter_shadcn theme --list
flutter_shadcn theme --apply modern-minimal
```

Expected:

- `theme --list` shows the published registry theme list
- `theme --apply` downloads generated Dart theme artifacts
- every downloaded theme file is hash-verified before writing
- if any file fails validation or hashing, no theme files are written

Verify the installed files:

```bash
find lib -path '*shadcn/shared/theme*' | sort
cat .shadcn/state.json
```

Expected:

- theme files exist at the targets declared by the registry
- selected theme state is recorded
- no runtime registry code execution occurs

### Experimental advanced theme inputs

These are not public workflow commands. Test them only with `--advanced`.

```bash
flutter_shadcn --advanced theme --apply-file /absolute/path/to/theme-artifact-manifest.json
flutter_shadcn --advanced theme --apply-url 'https://example.com/theme-artifact-manifest.json'
```

Expected:

- the command accepts only declarative artifact manifests
- the CLI never downloads and executes converter code
- invalid hashes or unsafe target paths abort the install before any write

## 7. Test Assets

```bash
flutter_shadcn assets --list
flutter_shadcn assets --typography
flutter_shadcn assets --icons
flutter_shadcn assets --all
```

Expected:

- assets are installed only through inline registry actions
- skipped or unavailable asset groups are reported clearly
- `pubspec.yaml` stays aligned with copied asset files

## 8. Test Reset and Recovery

### Global reset

Run from anywhere:

```bash
flutter_shadcn reset
```

Expected:

- asks for confirmation
- removes only global CLI cache/state under the home directory
- does not touch the current Flutter project

### Project reset

```bash
flutter_shadcn project reset
```

Expected:

- asks for confirmation
- snapshots managed project files before deleting them
- prints the undo window and exact expiry time

Undo within 24 hours:

```bash
flutter_shadcn project reset --undo
```

Expected:

- restores the deleted managed files
- refuses undo after the TTL expires

### Project refresh

Break the scaffold deliberately, then repair it:

```bash
rm -rf lib/ui/shadcn/shared
flutter_shadcn project refresh
```

Expected:

- recreates missing scaffold files only
- does not overwrite valid existing scaffold files
- does not touch installed user component code

## 9. Test Diagnostics and Sync

```bash
flutter_shadcn validate
flutter_shadcn audit
flutter_shadcn deps
flutter_shadcn sync
```

Expected:

- `validate` checks manifest and installed-file consistency
- `audit` reports project or registry issues clearly
- `deps` reports managed dependencies
- `sync` reconciles config-driven outputs without reintroducing removed legacy behavior

## 10. Test Crash Reporting

Force a controlled failure in a disposable environment if you are validating crash reporting behavior.

What to check:

- the CLI writes a crash log under `~/.flutter_shadcn/crashes/`
- only the 10 most recent crash logs are kept
- redacted flags keep the flag names and replace only values with `<redacted>`
- if stdin is interactive, the CLI prompts before opening a GitHub issue
- if stdin is not a TTY, it skips the prompt and just writes the log

## 11. AI-Assisted Test Flow

Use an agent when you want the CLI exercised repeatedly against local registries and real project state.

Recommended AI test brief:

```text
Use a throwaway Flutter app.
Run flutter_shadcn commands as a real user would.
Use --advanced only for developer or experimental commands.
If testing unpublished registry content, use --registries-path and --registry-path.
After each command:
- report exit code
- report stderr/stdout summary
- list files created, changed, or removed
- inspect .shadcn/config.json and .shadcn/state.json
- stop on the first unexpected mutation
```

Recommended command matrix for AI execution:

1. `flutter_shadcn version`
2. `flutter_shadcn doctor`
3. `flutter_shadcn init --yes`
4. `flutter_shadcn list --json`
5. `flutter_shadcn search button --json`
6. `flutter_shadcn info @shadcn/button --json`
7. `flutter_shadcn dry-run @shadcn/button --json`
8. `flutter_shadcn add @shadcn/button`
9. `flutter_shadcn theme --list`
10. `flutter_shadcn theme --apply <theme-id>`
11. `flutter_shadcn assets --list`
12. `flutter_shadcn validate --json`
13. `flutter_shadcn audit --json`
14. `flutter_shadcn deps --json`
15. `flutter_shadcn project refresh`
16. `flutter_shadcn project reset`
17. `flutter_shadcn project reset --undo`

For advanced-only validation, add:

1. `flutter_shadcn --advanced theme --apply-file /absolute/path/to/manifest.json`
2. `flutter_shadcn --advanced theme --apply-url 'https://example.com/manifest.json'`
3. `flutter_shadcn --advanced init shadcn --registries-path ... --registry-path ... --skip-integrity --yes`

## 12. Release Gate

Before shipping a CLI change, pair manual testing with the repository verification gates:

```bash
dart analyze
dart test
```

For registry or theme generation changes, also verify the source package directly:

```bash
cd /absolute/path/to/shadcn_flutter_kit/flutter_shadcn_kit
dart run tool/theme/theme_index_generate.dart --output manifests/theme.index.json
dart analyze lib/registry/shared/theme tool/theme/theme_preset_json_to_dart.dart tool/theme/theme_index_generate.dart test/tool/theme_tooling_test.dart
flutter test test/tool/theme_tooling_test.dart
```
