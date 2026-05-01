# Manual Testing Guide

Use this guide when validating a CLI build outside automated tests. Start from a clean Flutter project and run commands from the project root unless a step says otherwise.

## 1. Prepare a Clean Project

```bash
flutter create shadcn_cli_manual_test
cd shadcn_cli_manual_test
flutter_shadcn version
flutter_shadcn doctor
```

Expected:

- `version` prints the installed CLI version.
- `doctor` reports the Flutter project status.
- No `.shadcn/` directory exists until `init` runs.

## 2. Initialize the Default Registry

```bash
flutter_shadcn init --yes
```

Expected:

- `.shadcn/config.json` exists.
- `.shadcn/state.json` exists.
- Inline init actions create any registry-defined shared files, assets, fonts, and `pubspec.yaml` changes.
- The command uses the current init flow only.

Then run:

```bash
flutter_shadcn doctor
flutter pub get
```

Expected:

- `doctor` recognizes the initialized project.
- `flutter pub get` succeeds.

## 3. Inspect Registries and Components

```bash
flutter_shadcn registries
flutter_shadcn default
flutter_shadcn list
flutter_shadcn search button
flutter_shadcn info @shadcn/button
```

Expected:

- `registries` shows enabled registries.
- `default` prints the current default namespace.
- `list` and `search` show registry components.
- `info` prints component details for the namespaced address.

Repeat JSON-capable commands:

```bash
flutter_shadcn registries --json
flutter_shadcn list --json
flutter_shadcn search button --json
flutter_shadcn info @shadcn/button --json
```

Expected:

- Each command prints valid JSON.

## 4. Add Components

```bash
flutter_shadcn dry-run @shadcn/button
flutter_shadcn add @shadcn/button
flutter_shadcn add @shadcn/card @shadcn/dialog
```

Expected:

- `dry-run` shows planned files without writing them.
- `add` writes files under the configured install root.
- `.shadcn/components/` contains component manifests.
- `.shadcn/state.json` preserves managed dependency state.
- `pubspec.yaml` includes required managed dependencies.

Check unqualified resolution:

```bash
flutter_shadcn add button
```

Expected:

- The command succeeds only when `button` is unique across enabled registries.
- If multiple enabled registries provide `button`, the command fails and asks for a namespaced address.

## 5. Remove Components

```bash
flutter_shadcn remove @shadcn/card
flutter_shadcn remove @shadcn/dialog --force
```

Expected:

- Installed files and manifests for removed components are deleted.
- Shared files and dependencies still required by other installed components remain.
- Dependency conflicts are blocked unless `--force` is supplied.

## 6. Assets and Themes

```bash
flutter_shadcn assets --typography
flutter_shadcn assets --icons
flutter_shadcn assets --fonts
flutter_shadcn theme --list
```

Expected:

- Asset commands run through current registry inline actions.
- No old asset fallback component IDs are used.
- `theme --list` shows available themes when the registry supports themes.

If themes are available:

```bash
flutter_shadcn theme --apply <theme-id>
flutter_shadcn theme widget --list
```

Expected:

- `.shadcn/config.json` and `.shadcn/state.json` reflect the selected theme.
- Widget theme commands operate only on supported registry theme data.

## 7. Platform Targets

```bash
flutter_shadcn platform --list
flutter_shadcn platform --set ios=lib/platform/ios.dart
flutter_shadcn platform --list
flutter_shadcn platform --reset ios
```

Expected:

- Platform targets are listed, added, and reset in project config.

## 8. Diagnostics

```bash
flutter_shadcn validate
flutter_shadcn audit
flutter_shadcn deps
flutter_shadcn sync
```

Expected:

- `validate` reports manifest and installed-file consistency.
- `audit` reports registry/project issues.
- `deps` reports managed dependencies.
- `sync` reconciles current registry metadata with installed state.

## 9. Developer Local Registry Smoke Test

Developer-only local registry testing is documented in [../developer/local-registry-development.md](../developer/local-registry-development.md).

Minimum smoke test:

```bash
flutter_shadcn init shadcn --registries-path /absolute/path/to/registries.json --registry-path /absolute/path/to/local/registry --skip-integrity --yes
flutter_shadcn add @shadcn/button --registries-path /absolute/path/to/registries.json --registry-path /absolute/path/to/local/registry --skip-integrity
```

Expected:

- Hidden developer overrides route through the current multi-registry engine.
- Local unpublished registry files can be tested without changing public command behavior.

## 10. Automated Verification Gates

Run these from the CLI repository:

```bash
dart analyze
dart test test/resolver_v1_test.dart test/config_state_migration_test.dart test/registry_directory_test.dart test/init_action_engine_test.dart test/multi_registry_manager_test.dart test/e2e_multi_registry_fixture_test.dart --reporter=expanded
dart test test/cli_integration_test.dart --concurrency=1 --reporter=expanded
dart test
```

All gates must pass before releasing documentation or CLI changes.
