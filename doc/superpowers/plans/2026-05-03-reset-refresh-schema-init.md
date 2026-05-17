# Reset, Refresh, and Schema-Driven Init Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add global `reset`, project `reset`/`refresh`, and schema-driven init prompting while preserving current multi-registry behavior.

**Architecture:** Introduce focused services for reset snapshot storage and project refresh, keep CLI parsing/dispatch thin, and extend the existing init action engine to consume additive registry schema fields at runtime. Reuse current config/state/journal structures where they are reliable, but store undo snapshots outside the project so reset can remove `.shadcn/` safely.

**Tech Stack:** Dart CLI, `args`, existing init action engine, existing config/state loaders, filesystem IO, existing docs generator and command metadata surfaces.

---

## File Map

- Create: `lib/src/application/services/reset/reset_snapshot_store.dart`
- Create: `lib/src/application/services/reset/reset_snapshot_manifest.dart`
- Create: `lib/src/application/services/reset/global_reset_service.dart`
- Create: `lib/src/application/services/reset/project_reset_service.dart`
- Create: `lib/src/application/services/reset/project_refresh_service.dart`
- Create: `lib/src/presentation/cli/commands/reset_command.dart`
- Create: `lib/src/presentation/cli/commands/project_command.dart`
- Create: `test/reset_command_test.dart`
- Create: `test/project_reset_service_test.dart`
- Create: `test/project_refresh_service_test.dart`
- Modify: `lib/src/presentation/cli/cli_parser.dart`
- Modify: `lib/src/presentation/cli/bootstrap.dart`
- Modify: `lib/src/presentation/cli/usage.dart`
- Modify: `lib/src/presentation/cli/command_metadata.dart`
- Modify: `lib/src/schemas/registries.schema.json`
- Modify: `lib/src/application/services/init_action_engine/init_action_engine.dart`
- Modify: `lib/src/application/services/init_action_engine/init_execution_record_part.dart`
- Modify: `lib/src/application/services/init_action_engine/init_execution_result_part.dart`
- Modify: `lib/src/application/services/init_action_engine/init_pubspec_delta_part.dart`
- Modify: `lib/src/application/services/multi_registry/multi_registry_init_part.dart`
- Modify: `test/init_action_engine_test.dart`
- Modify: `test/cli_parser_test.dart`
- Modify: `test/cli_integration_test.dart`

### Task 1: Reset Snapshot Infrastructure

**Files:**
- Create: `lib/src/application/services/reset/reset_snapshot_store.dart`
- Create: `lib/src/application/services/reset/reset_snapshot_manifest.dart`
- Create: `lib/src/application/services/reset/project_reset_service.dart`
- Test: `test/project_reset_service_test.dart`

- [ ] **Step 1: Write failing snapshot tests**

Write tests for:
- creating a snapshot in `~/.flutter_shadcn/project-resets/<hash>/`
- copying tracked project files into the snapshot bundle
- storing `createdAtUtc` and `expiresAtUtc`
- restoring files on `--undo`
- refusing restore after expiry
- pruning expired snapshots

- [ ] **Step 2: Run the snapshot tests and verify failure**

Run:

```bash
dart test test/project_reset_service_test.dart --reporter=expanded
```

Expected: failures for missing reset snapshot store/service.

- [ ] **Step 3: Implement the snapshot manifest and store**

Implement a manifest with:
- project path
- created/expires timestamps
- relative file list
- deleted directory roots

Store snapshots outside the project under the user home directory. Use a stable hash of normalized project root as the snapshot key.

- [ ] **Step 4: Implement project reset / undo**

`project reset` must:
- discover CLI-owned project artifacts
- snapshot them first
- delete them
- print undo window + exact expiry time

`project reset --undo` must:
- find the latest non-expired snapshot for the project
- restore files exactly
- restore directories as needed

- [ ] **Step 5: Re-run snapshot tests**

Run:

```bash
dart test test/project_reset_service_test.dart --reporter=expanded
```

Expected: PASS.

### Task 2: Global Reset and CLI Wiring

**Files:**
- Create: `lib/src/application/services/reset/global_reset_service.dart`
- Create: `lib/src/presentation/cli/commands/reset_command.dart`
- Create: `lib/src/presentation/cli/commands/project_command.dart`
- Modify: `lib/src/presentation/cli/cli_parser.dart`
- Modify: `lib/src/presentation/cli/bootstrap.dart`
- Modify: `lib/src/presentation/cli/usage.dart`
- Modify: `lib/src/presentation/cli/command_metadata.dart`
- Test: `test/reset_command_test.dart`
- Test: `test/cli_parser_test.dart`

- [ ] **Step 1: Write failing command/parser tests**

Add tests for:
- `flutter_shadcn reset` prompting before deleting global CLI state
- `flutter_shadcn project reset`
- `flutter_shadcn project reset --undo`
- `flutter_shadcn project refresh`
- help text and command metadata visibility

- [ ] **Step 2: Run the targeted tests and verify failure**

Run:

```bash
dart test test/reset_command_test.dart test/cli_parser_test.dart --reporter=expanded
```

Expected: failures because parser/commands do not exist.

- [ ] **Step 3: Implement global reset scope**

Delete only global CLI-owned state, not project files:
- `~/.flutter_shadcn/cache`
- crash logs
- reset snapshots
- other CLI-managed home-directory artifacts

Do not uninstall the globally activated executable.

- [ ] **Step 4: Wire parser, dispatch, usage, metadata**

Add:
- top-level `reset`
- top-level `project` with subcommands `reset` and `refresh`

Keep behavior user-facing. Do not gate these commands behind `--advanced`.

- [ ] **Step 5: Re-run targeted command tests**

Run:

```bash
dart test test/reset_command_test.dart test/cli_parser_test.dart --reporter=expanded
```

Expected: PASS.

### Task 3: Project Refresh Repair Flow

**Files:**
- Create: `lib/src/application/services/reset/project_refresh_service.dart`
- Test: `test/project_refresh_service_test.dart`

- [ ] **Step 1: Write failing refresh tests**

Cover:
- detecting missing scaffold files after init
- regenerating only missing files
- not overwriting existing valid files
- not touching installed component files
- re-offering optional init actions that were previously skipped because they are absent

- [ ] **Step 2: Run refresh tests and verify failure**

Run:

```bash
dart test test/project_refresh_service_test.dart --reporter=expanded
```

Expected: failures because refresh service does not exist.

- [ ] **Step 3: Implement refresh discovery**

Use project config/state plus registry init declaration to derive expected scaffold outputs. Compare expected scaffold outputs against actual files and re-run only the missing subset through the init action engine.

- [ ] **Step 4: Re-run refresh tests**

Run:

```bash
dart test test/project_refresh_service_test.dart --reporter=expanded
```

Expected: PASS.

### Task 4: Schema Update and Schema-Driven Init Prompts

**Files:**
- Modify: `lib/src/schemas/registries.schema.json`
- Modify: `lib/src/application/services/init_action_engine/init_action_engine.dart`
- Modify: `lib/src/application/services/init_action_engine/init_execution_record_part.dart`
- Modify: `lib/src/application/services/init_action_engine/init_execution_result_part.dart`
- Modify: `lib/src/application/services/init_action_engine/init_pubspec_delta_part.dart`
- Modify: `lib/src/application/services/multi_registry/multi_registry_init_part.dart`
- Test: `test/init_action_engine_test.dart`
- Test: `test/cli_integration_test.dart`

- [ ] **Step 1: Write failing init-engine tests**

Add tests for:
- schema accepts `optional`, `promptLabel`, `promptDescription`, `groups`, `deriveFlutterAssets`
- non-optional actions run silently
- optional actions prompt and skip cleanly
- grouped `copyFiles` copies only selected groups
- `deriveFlutterAssets` adds only asset-compatible written paths
- skipped groups do not enter `pubspec.yaml`
- no theme/font prompts when the registry entry omits those sections

- [ ] **Step 2: Run targeted init tests and verify failure**

Run:

```bash
dart test test/init_action_engine_test.dart test/cli_integration_test.dart --reporter=expanded
```

Expected: failures around unsupported schema fields and missing prompt behavior.

- [ ] **Step 3: Update bundled schema**

Bring `lib/src/schemas/registries.schema.json` in sync with the source-of-truth schema fields needed by the runtime.

- [ ] **Step 4: Extend init engine execution model**

Add:
- action selection model for optional actions
- grouped file expansion for `copyFiles`
- accumulation of actually written asset paths during the current init run
- merge behavior for `deriveFlutterAssets` + explicit `flutterAssets`

Keep path construction strict: use only registry entry fields, no invented prefixes.

- [ ] **Step 5: Move prompt orchestration to runtime-declared actions**

`runNamespaceInit` should inspect the registry entry and ask only for optional actions/groups that exist. Remove hard-coded theme/font assumptions where the schema already declares behavior.

- [ ] **Step 6: Re-run targeted init tests**

Run:

```bash
dart test test/init_action_engine_test.dart test/cli_integration_test.dart --reporter=expanded
```

Expected: PASS.

### Task 5: Full Verification and Graph Refresh

**Files:**
- Modify: `PROGRESS.md`

- [ ] **Step 1: Run analysis**

```bash
dart analyze
```

- [ ] **Step 2: Run targeted gates**

```bash
dart test test/reset_command_test.dart test/project_reset_service_test.dart test/project_refresh_service_test.dart test/init_action_engine_test.dart test/cli_parser_test.dart test/cli_integration_test.dart --reporter=expanded
```

- [ ] **Step 3: Run full test suite**

```bash
dart test
```

- [ ] **Step 4: Refresh graph**

```bash
graphify update .
```

- [ ] **Step 5: Update progress tracking**

Record completed phases and any deliberate follow-ups in `PROGRESS.md`.
