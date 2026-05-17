# Init Pubspec Merge and Exit Behavior Design

## Scope

Fix two user-facing problems in the current CLI:

1. `flutter_shadcn init` can place `assets:` and `fonts:` under `dependencies:` instead of under `flutter:` in `pubspec.yaml`.
2. Normal CLI commands can feel slow to exit because they kick off background update checking after command work is already complete.

## Root Cause

### Pubspec corruption

`InitActionEngine._runMergePubspec()` currently edits `pubspec.yaml` as a list of plain lines. The helper methods that locate and extend `flutter:`, `assets:`, and `fonts:` sections are indentation-based and can misplace child sections when the input YAML shape varies.

### Slow command exit

`runCliBootstrap()` starts `VersionManager.autoCheckForUpdates()` with `unawaited(...)` for most commands. That background network work is unrelated to the user command and can keep the process alive or make command completion feel stale.

## Chosen Approach

### 1. Structural pubspec mutation

Replace line-oriented merging for `dependencies`, `dev_dependencies`, `flutter.assets`, and `flutter.fonts` with parsed YAML mutation.

Implementation constraints:

- preserve the existing `InitPubspecDelta` contract
- preserve rollback support
- write back valid `pubspec.yaml` with `assets:` and `fonts:` only under `flutter:`
- keep `deriveFlutterAssets` behavior intact

This fix is preferred over tightening the current line parser because the current model is structurally fragile and already produced invalid YAML.

### 2. Remove background update checks from normal command execution

Stop running automatic update checks during ordinary commands in `runCliBootstrap()`.

Allowed behaviors after this change:

- `upgrade` remains explicit
- `version` remains fast and deterministic
- any future update check should be explicit or opt-in, not launched in the background on unrelated commands

## Tests

Add or update tests to cover:

1. `mergePubspec` inserts `flutter.assets` and `flutter.fonts` under `flutter:` rather than `dependencies:`
2. rollback still removes inserted assets/fonts/dependencies correctly
3. normal command execution does not trigger background update checking

## Files Expected To Change

- `lib/src/application/services/init_action_engine/init_action_engine.dart`
- `lib/src/presentation/cli/bootstrap.dart`
- `test/init_action_engine_test.dart`
- additional targeted tests if needed for bootstrap behavior

## Non-Goals

- no broad rewrite of unrelated config/state logic
- no changes to public command semantics beyond removing silent background update checks
- no registry schema changes
