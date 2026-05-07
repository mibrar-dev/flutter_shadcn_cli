# V1 Gap Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the real and partial v1 multi-registry gaps without regressing the current single-registry, inline-init, migration, schema validation, path-guard, ambiguity, and `.shadcn/state.json.managedDependencies` behavior.

**Architecture:** Keep the current layered CLI shape: parser and command routing in `presentation`, orchestration in `application/services/multi_registry`, install behavior in `application/services/installer`, directory/schema fetch in `infrastructure/registry_directory`, and manifest models in `registry`. Add narrowly scoped policy, preflight, transaction, lockfile, and planning services instead of rewriting the installer.

**Tech Stack:** Dart CLI, `args`, `http`, `json_schema`, `yaml`, `path`, `crypto`, existing `.shadcn/config.json` and `.shadcn/state.json`, existing `registries.schema.json`, and focused Dart tests under `test/`.

---

## Scope Decisions

### Not Current Gaps

- **GAP-08:** Exclude. The current v1 spec and code do not implement the reviewed `pick_keys_preserve_user` localization merge strategy. Locale and manifest source-of-truth work belongs in Task 2.
- **GAP-11:** Exclude. The reviewed `required: false` localization-resource behavior is not a current implemented surface. Optional init actions already use explicit approval/skipping semantics, and localization-resource semantics belong in Task 2.
- **GAP-12:** Exclude. ARB-aware merge is not part of the current v1 code surface evidenced here. Locale/ARB design must be handled in Task 2.
- **GAP-13:** Exclude. Consumer `l10n.yaml` target resolution is not active in current v1 install/init behavior. This remains a locale source-of-truth topic for Task 2.
- **GAP-16:** Exclude. Locale filtering and fallback strategy are not current v1 behavior. Task 2 owns the detailed locale install/update contract.
- **GAP-20:** Exclude. The CLI command surface exists now: `init`, `add`, `dry-run`, `remove`, `sync`, `doctor`, `registries`, `list`, `search`, and related commands are registered in `cli_parser.dart`.

### Mostly Implemented Guard

- **GAP-04:** Mostly implemented. `registries.schema.json` pins `schemaVersion` to `1`, registry-directory validation is fatal, component schema validation is enforced for explicit schemas, and `minCliVersion` filtering exists. Do not create a broad compatibility-matrix task now. Add only the guard in Task 3: unsupported directory or explicit component manifest versions must fail before writes.

## Task 1: Tighten Registry Trust And Remote URL Policy (GAP-02)

**Problem**

The code verifies `components.json` when `trust.mode == sha256`, but normal remote registries can still be used without a clear trust policy, and non-HTTPS remote URLs are not rejected consistently at the boundary.

**How To Solve**

Add a single trust policy service used by registry-directory loading and registry-source resolution. Reject non-HTTPS remote URLs, allow local development paths, require explicit trust metadata for third-party remote registries, and keep `--skip-integrity` as a hidden developer-only bypass.

**What To Do**

- [ ] Add `RegistryTrustPolicy` with validation for directory URL, registry `baseUrl`, `componentsPath`, and trust metadata.
- [ ] Enforce HTTPS before fetching `registries.json`, `components.json`, theme artifacts, or registry source files.
- [ ] Require `trust.mode: sha256` with a non-empty `sha256` for third-party remote registries used by public `init` or `add`.
- [ ] Keep local `--registry-path`, local `registries-path`, and file-backed test registries accepted.
- [ ] Ensure `--skip-integrity` only bypasses hash validation in advanced/developer override flows.
- [ ] Emit one clear error per rejected registry, including namespace and offending URL.

**Edge Cases To Resolve**

- GitHub tree URLs normalized to `raw.githubusercontent.com` must remain HTTPS.
- Offline mode may use cache only if the cached registry was previously trusted.
- Empty or unknown `trust.mode` on remote registries must fail before any install action or component write.
- Local absolute paths must not be treated as remote URLs.

**Files likely touched**

- `lib/src/infrastructure/registry_directory/registry_directory_client.dart`
- `lib/src/infrastructure/registry_directory/registry_trust.dart`
- `lib/src/application/services/multi_registry/multi_registry_directory_part.dart`
- `lib/src/infrastructure/registry/registry_repository_adapter.dart`
- New: `lib/src/application/services/registry_trust_policy.dart`

**Tests to add/run**

- Add trust-policy tests in `test/registry_directory_test.dart` or new `test/registry_trust_policy_test.dart`.
- Add integration coverage in `test/cli_integration_test.dart` for HTTP rejection and missing trust rejection.
- Run: `dart test test/registry_directory_test.dart test/cli_integration_test.dart --concurrency=1 --reporter=expanded`
- Run: `dart analyze`

**Branch name suggestion**

- `branch-v1-gap-02-trust-policy`

## Task 2: Add Install Scope Policy And Target Sandboxing (GAP-01, GAP-03)

**Problem**

Traversal and symlink escape protections exist through `ResolverV1` and `ProjectPathGuard`, but registry-owned component file destinations can still target broad in-project paths. The remaining gap is per-registry install scope enforcement.

**How To Solve**

Introduce an install target policy that validates every component destination after variable expansion but before reads/writes. Keep inline init actions project-root-relative per spec, while requiring component files to stay inside registry-owned roots unless they are supported assets/fonts.

**What To Do**

- [ ] Add `InstallTargetPolicy` that accepts namespace, install root, shared root, file kind, and destination relative path.
- [ ] For component Dart/source files, require destinations under the registry install root or shared root.
- [ ] For component assets/fonts, allow only `assets/` paths and require exact paths to be recorded for pubspec updates.
- [ ] Reject component-file writes to `pubspec.yaml`, `.git/`, `.shadcn/config.json`, and `.shadcn/state.json`.
- [ ] Apply the policy in `_resolveDestinationPath` or immediately before `_installFile`.
- [ ] Preserve inline init behavior while keeping `ProjectPathGuard` on every init write.

**Edge Cases To Resolve**

- Existing single-registry defaults such as `lib/ui/shadcn` must keep working.
- Namespace-specific config overrides must produce the effective allowed root.
- Absolute paths that resolve inside the project root must be normalized and policy-checked.
- Generated aliases and installer-managed manifests are first-party CLI writes and should use existing guarded paths, not registry component policy.

**Files likely touched**

- `lib/src/application/services/installer/installer_file_install_part.dart`
- `lib/src/application/services/installer/installer_pubspec_part.dart`
- `lib/src/application/services/installer/installer_manifest_part.dart`
- New: `lib/src/application/services/installer/install_target_policy.dart`
- `test/installer_test.dart`
- `test/e2e_multi_registry_fixture_test.dart`

**Tests to add/run**

- Add tests rejecting component destinations to `lib/main.dart`, `.shadcn/state.json`, `../outside.dart`, and symlink escapes.
- Add tests allowing `lib/ui/<namespace>/components/button/button.dart`, shared files under the shared root, and explicit `assets/<namespace>/...` assets.
- Run: `dart test test/installer_test.dart test/e2e_multi_registry_fixture_test.dart --reporter=expanded`
- Run: `dart analyze`

**Branch name suggestion**

- `branch-v1-gap-01-03-install-scope`

## Task 3: Preflight Manifest Validation And Version Guards (GAP-04, GAP-05)

**Problem**

Directory schema validation and explicit component schema validation exist, but validation is split across loaders and compatibility paths. Install must fail before any file, pubspec, state, cache, or manifest write if the active registry manifest is invalid or version-unsupported.

**How To Solve**

Centralize active manifest preflight into a read-only validation step after registry source resolution and before installer construction. Make unsupported `schemaVersion` fatal for the registry directory and explicit component schemas. Preserve the documented implicit missing component-schema compatibility path until the spec removes it.

**What To Do**

- [ ] Add `RegistryManifestPreflight` for directory entries, active registry source, active `components.json`, and schema version checks.
- [ ] Require directory `schemaVersion == 1` using existing schema validation plus a defensive direct assertion.
- [ ] Require explicit component schema validation before `init`, `add`, `dry-run`, `assets`, or preload installs perform writes.
- [ ] Report all `json_schema` validation failures together.
- [ ] Keep hidden `--skip-integrity` semantics limited to developer explicit schema/hash bypass.
- [ ] Add a regression test proving invalid explicit schema fails with zero project writes.

**Edge Cases To Resolve**

- Offline cached invalid manifests must still fail validation.
- JSON decode failures should be typed and user-readable.
- `init <namespace>` without inline actions must validate `registries.json` but must not require `components.json`.
- `init <namespace>` with inline actions must not fetch `meta.json`.

**Files likely touched**

- `lib/src/registry/registry_model.dart`
- `lib/src/registry/components_schema_validator.dart`
- `lib/src/infrastructure/registry_directory/registry_directory_client.dart`
- `lib/src/application/services/multi_registry/multi_registry_directory_part.dart`
- New: `lib/src/application/services/registry_manifest_preflight.dart`

**Tests to add/run**

- Add zero-write validation tests to `test/schema_validation_test.dart`.
- Add CLI invalid-schema tests to `test/cli_integration_test.dart`.
- Run: `dart test test/schema_validation_test.dart test/registry_directory_test.dart test/cli_integration_test.dart --concurrency=1 --reporter=expanded`
- Run: `dart analyze`

**Branch name suggestion**

- `branch-v1-gap-04-05-manifest-preflight`

## Task 4: Transactional Component Add And Init Commit/Rollback (GAP-06)

**Problem**

Inline init has rollback records, but component install writes files, platform instructions, aliases, component manifests, state, and pubspec changes progressively. A failure can leave a partial install.

**How To Solve**

Add an install transaction coordinator. It should snapshot existing files before modification, record rollback operations, apply all changes, and automatically restore the previous state if any step fails.

**What To Do**

- [ ] Add `InstallTransaction` with `recordFileWrite`, `recordFileDelete`, `recordDirectoryCreate`, `recordPubspecBefore`, `commit`, and `rollback`.
- [ ] Wrap component files, platform instructions, manifests, state, aliases, and pubspec updates in a transaction for `add`.
- [ ] Update inline init execution to use the same transaction model while preserving `InitExecutionRecord`.
- [ ] Roll back created files, restore overwritten files byte-for-byte, restore modified pubspec, and remove empty directories created by the operation.
- [ ] Keep `dry-run` read-only and use it as preview, not staging.

**Edge Cases To Resolve**

- Existing user files skipped because overwrite is false must not be rolled back or deleted.
- If rollback fails, report rollback failures while keeping the original install error visible.
- Concurrent component file copy must coordinate transaction records without races.
- State and manifest writes should happen after file writes but before final commit completes.

**Files likely touched**

- `lib/src/application/services/installer/installer.dart`
- `lib/src/application/services/installer/installer_file_install_part.dart`
- `lib/src/application/services/installer/installer_manifest_part.dart`
- `lib/src/application/services/installer/installer_pubspec_part.dart`
- `lib/src/application/services/init_action_engine/init_action_engine.dart`
- New: `lib/src/application/services/installer/install_transaction.dart`

**Tests to add/run**

- Add installer failure tests proving no partial files, aliases, manifests, state, or pubspec edits remain after a simulated failure.
- Add init action failure tests proving copied files and pubspec deltas are rolled back.
- Run: `dart test test/installer_test.dart test/init_action_engine_test.dart --reporter=expanded`
- Run: `dart analyze`

**Branch name suggestion**

- `branch-v1-gap-06-install-transactions`

## Task 5: Qualified Component Identity Everywhere (GAP-07)

**Problem**

`add` resolution accepts `@namespace/component` and rejects ambiguous unqualified adds, but installed state and manifests still use bare component IDs in places. Remove, sync, doctor, and update-style operations cannot reliably distinguish the same component ID installed from multiple registries.

**How To Solve**

Introduce a canonical `QualifiedComponentId` model and migrate internal state/manifests to namespace plus component ID. Keep user-facing unqualified input only when it resolves uniquely. Read old bare manifests as a migration path.

**What To Do**

- [ ] Add `QualifiedComponentId` with canonical `@namespace/component`, storage fields, and legacy bare-ID compatibility.
- [ ] Store component manifests under a namespaced layout such as `.shadcn/components/<namespace>/<componentId>.json`.
- [ ] Store namespace, component ID, registry source, component version, and source manifest hash in every component manifest.
- [ ] Update installed-component discovery to return qualified records.
- [ ] Update remove, dry-run, sync, doctor, list/info output paths to use qualified identity internally.
- [ ] Migrate old `.shadcn/components/<componentId>.json` into namespaced records using the current default namespace when no namespace is stored.

**Edge Cases To Resolve**

- Two enabled registries with `button` installed must not overwrite each other's manifest.
- Existing single-registry projects must read old bare IDs and save upgraded qualified records.
- Error messages should recommend `@namespace/component`.
- `.shadcn/state.json.managedDependencies` behavior must remain intact.

**Files likely touched**

- `lib/src/application/dto/qualified_component_ref.dart`
- `lib/src/application/services/add_resolution_service.dart`
- `lib/src/application/services/installer/installer_manifest_part.dart`
- `lib/src/application/services/installer/installer_remove_part.dart`
- `lib/src/application/services/installer/installer_dry_run_part.dart`
- `lib/src/application/services/multi_registry/multi_registry_add_part.dart`
- `test/add_resolution_service_test.dart`
- `test/config_state_migration_test.dart`
- `test/cli_integration_test.dart`

**Tests to add/run**

- Add tests for installing `@a/button` and `@b/button` in the same project.
- Add migration tests for legacy bare manifests.
- Add remove/dry-run tests proving qualified selection targets the correct registry.
- Run: `dart test test/add_resolution_service_test.dart test/config_state_migration_test.dart test/cli_integration_test.dart --concurrency=1 --reporter=expanded`
- Run: `dart analyze`

**Branch name suggestion**

- `branch-v1-gap-07-qualified-installed-identity`

## Task 6: Remove Hand-Authored Capability Flags As Install Authority (GAP-09)

**Problem**

Directory/config capability flags still exist. They may be useful for browsing, but if they control install behavior they become a second source of truth that can diverge from component data.

**How To Solve**

Demote capability flags to display-only metadata. Install decisions must derive from actual component, shared, init, theme, asset, and pubspec declarations.

**What To Do**

- [ ] Identify every use of `capabilitySharedGroups`, `capabilityComposites`, and `capabilityTheme`.
- [ ] Replace install decisions with checks against actual manifest data.
- [ ] Keep directory `capabilities` visible in `registries` output only as advertised metadata.
- [ ] Add derived capabilities in discovery output where component manifests are already loaded.
- [ ] Avoid using hand-authored flags to suppress shared group expansion when component data declares shared dependencies.

**Edge Cases To Resolve**

- Registries without capability flags but with shared groups must still install shared files.
- Registries with stale false flags but actual shared declarations must not skip dependencies.
- Lightweight directory listing should not fetch every `components.json` solely to derive capabilities unless the command already requests detail data.
- Existing config files containing capability fields must still deserialize.

**Files likely touched**

- `lib/src/config/registry_config_entry.dart`
- `lib/src/infrastructure/registry_directory/registry_capabilities.dart`
- `lib/src/application/services/multi_registry/multi_registry_directory_part.dart`
- `lib/src/application/services/multi_registry/multi_registry_add_part.dart`
- `docs/user/registries.md`

**Tests to add/run**

- Add multi-registry tests where advertised capabilities are false but manifest data requires shared install.
- Add registries listing tests verifying advertised versus derived fields.
- Run: `dart test test/multi_registry_manager_test.dart test/cli_integration_test.dart --concurrency=1 --reporter=expanded`
- Run: `dart analyze`

**Branch name suggestion**

- `branch-v1-gap-09-derived-capabilities`

## Task 7: Lockfile And Manifest Source Of Truth (GAP-10, GAP-14, GAP-18, GAP-21, GAP-22)

**Problem**

The CLI writes `.shadcn/state.json` and component manifests, but there is no project-level lockfile source of truth for reproducible sync, doctor, update, uninstall, source hashes, or version pins.

**How To Solve**

Create a v1 lockfile service as the source of truth for installed registry components. Keep `.shadcn/state.json.managedDependencies` unchanged for compatibility, but move reproducibility, sync, doctor, update planning, and uninstall ownership into lockfile records. This task references locale/manifest ownership but leaves detailed locale key semantics to Task 2.

**What To Do**

- [ ] Add `shadcn.lock` with `lockfileVersion: 1`, registry entries, installed components, component versions, source manifest hash, installed files, pubspec dependency ownership, post-install notes, and optional locale key ownership placeholders.
- [ ] Update `add` to write one lockfile record after successful transaction commit.
- [ ] Update `remove` to delete files and pubspec dependencies based on lock ownership.
- [ ] Update `sync` to read the lockfile and reinstall exactly locked namespace/component/version records.
- [ ] Update `doctor` to check lockfile records: files exist, dependencies exist, component manifest exists, required post-install notes remain visible, and source hashes are available.
- [ ] Add parser/model support for `@namespace/component@version`, while unversioned install selects the registry's current component version.
- [ ] Add update planning as an explicit dry-run/report operation before transactional update writes.

**Edge Cases To Resolve**

- Legacy projects with no `shadcn.lock` must synthesize records from existing `.shadcn/components` manifests and current state.
- Two registries with the same component ID must produce separate lock records.
- Missing version in old manifests should be stored as `null` or `unknown`, not guessed.
- Source manifest hash should be computed from the fetched `components.json` body.
- Locale key ownership must be represented as fields reserved for Task 2, without implementing locale merge behavior here.
- `.shadcn/state.json.managedDependencies` must continue to be saved exactly as current behavior expects.

**Files likely touched**

- New: `lib/src/application/services/lockfile/shadcn_lock.dart`
- New: `lib/src/application/services/lockfile/shadcn_lock_repository.dart`
- `lib/src/application/services/installer/installer_manifest_part.dart`
- `lib/src/application/services/installer/installer_remove_part.dart`
- `lib/src/application/services/installer/installer_dry_run_part.dart`
- `lib/src/application/services/multi_registry/multi_registry_add_part.dart`
- `lib/src/presentation/cli/commands/sync_command.dart`
- `lib/src/presentation/cli/commands/doctor_command.dart`
- `lib/src/presentation/cli/cli_parser.dart`

**Tests to add/run**

- Add lockfile serialization and migration tests.
- Add add/remove/sync/doctor integration tests with two registries and same component ID.
- Add version parser tests for `@namespace/button@1.2.0`.
- Run: `dart test test/cli_parser_test.dart test/installer_test.dart test/multi_registry_manager_test.dart test/cli_integration_test.dart --concurrency=1 --reporter=expanded`
- Run: `dart analyze`

**Branch name suggestion**

- `branch-v1-gap-10-14-lockfile-source-of-truth`

## Task 8: Pubspec Conflict Policy And Dependency Ownership (GAP-15)

**Problem**

Pubspec updates mix direct text insertion and `dart pub add/remove`. Existing dependencies are skipped silently, version conflicts are not surfaced, and removals rely on `managedDependencies` plus registry-wide dependency collection.

**How To Solve**

Replace silent mutation with a deterministic pubspec planner. It should classify additions, already-satisfied constraints, conflicts, and removals based on lockfile ownership. Never overwrite an existing user constraint without explicit opt-in.

**What To Do**

- [ ] Add `PubspecChangePlanner` that computes add/keep/conflict/remove operations.
- [ ] If an existing dependency constraint differs from the component constraint, fail in non-interactive mode with a clear conflict.
- [ ] In interactive mode, allow keep existing, update to registry constraint, or abort.
- [ ] Record dependency ownership in the lockfile per qualified component.
- [ ] Remove a dependency only when no remaining lockfile component owns it and it was originally CLI-managed.
- [ ] Keep `.shadcn/state.json.managedDependencies` updated from lockfile-owned dependencies plus current core init dependencies.

**Edge Cases To Resolve**

- Path, git, hosted, SDK, and map-shaped dependencies must not be collapsed to strings.
- Existing comments near dependencies should remain in place.
- Dev dependencies must not be modified unless the manifest explicitly declares `dev_dependencies`.
- A dependency used by two components with the same constraint must be removed only after both are removed.

**Files likely touched**

- `lib/src/application/services/installer/installer_pubspec_part.dart`
- `lib/src/application/services/init_action_engine/init_action_engine.dart`
- New: `lib/src/application/services/pubspec/pubspec_change_planner.dart`
- `lib/src/application/services/lockfile/shadcn_lock.dart`
- `test/installer_test.dart`
- `test/init_action_engine_test.dart`

**Tests to add/run**

- Add tests for existing same constraint, conflicting constraint, map-shaped dependency, shared ownership, and safe removal.
- Add init merge tests proving comments and unrelated sections survive.
- Run: `dart test test/installer_test.dart test/init_action_engine_test.dart --reporter=expanded`
- Run: `dart analyze`

**Branch name suggestion**

- `branch-v1-gap-15-pubspec-policy`

## Task 9: Dependency Graph Cycle Detection (GAP-17)

**Problem**

Current install and dry-run paths skip recursion-stack repeats instead of failing. That prevents infinite recursion but hides invalid registry data and can leave dependency closure incomplete.

**How To Solve**

Build and validate the component/shared dependency graph before writes. If a cycle exists, abort with a clear cycle path and do not install anything.

**What To Do**

- [ ] Add `RegistryDependencyGraph` including component `dependsOn`, component `shared`, shared-to-shared dependencies, and applicable file dependency ownership.
- [ ] Run cycle detection in dry-run and add preflight before installing the first file.
- [ ] Return a typed exception containing the exact path, for example `button -> form_control -> button`.
- [ ] Remove silent cycle skipping from `addComponent` once preflight guarantees acyclic input.
- [ ] Keep missing dependencies as a separate error from cycles.

**Edge Cases To Resolve**

- Self-cycle `button -> button` must fail.
- Optional file dependencies should not create hard install cycles unless required for installation.
- Bulk `add --all` should validate the whole graph once.
- Component-to-shared and shared-to-component relationships must follow only relationships represented by current models.

**Files likely touched**

- `lib/src/application/services/installer/installer.dart`
- `lib/src/application/services/installer/installer_dry_run_part.dart`
- `lib/src/application/services/installer/installer_shared_part.dart`
- New: `lib/src/application/services/registry_dependency_graph.dart`
- `test/installer_test.dart`

**Tests to add/run**

- Add tests for component cycles, shared cycles, self-cycles, missing dependencies, and no-write abort behavior.
- Run: `dart test test/installer_test.dart --reporter=expanded`
- Run: `dart analyze`

**Branch name suggestion**

- `branch-v1-gap-17-cycle-detection`

## Task 10: Asset Copy And Pubspec Semantics (GAP-19)

**Problem**

Assets can be declared as component `assets`, fonts, and derived inline-init assets. Binary assets must not use merge strategies, overwrite policy must be explicit, and pubspec updates must add exact file paths rather than broad directories unless explicitly designed.

**How To Solve**

Add asset-specific manifest validation and copy policy. Treat component `assets` and inline copied files as concrete file paths. Support only `copy` and `copy_preserve_user` for binary assets.

**What To Do**

- [ ] Extend registry file/action parsing with optional `strategy` for assets where schema allows it.
- [ ] Default asset strategy to `copy_preserve_user` for user-visible assets and existing inline `overwrite: false` behavior.
- [ ] Reject merge strategies for `.png`, `.jpg`, `.webp`, `.ttf`, `.otf`, `.woff`, `.woff2`, and `.svg`.
- [ ] Ensure `flutter.assets` receives exact file paths copied by the operation.
- [ ] Warn when an existing asset is preserved rather than overwritten.
- [ ] Record asset ownership in the lockfile for remove/sync/doctor.

**Edge Cases To Resolve**

- SVG is text but should still be treated as non-merge for v1 unless a safe SVG merge strategy is specified later.
- Directories should not be added to `flutter.assets` by default.
- Existing asset files with user modifications must not be overwritten by preserve strategy.
- Inline init derived assets should only include files that were actually written.

**Files likely touched**

- `lib/src/application/services/init_action_engine/init_action_engine.dart`
- `lib/src/application/services/installer/installer_file_install_part.dart`
- `lib/src/application/services/installer/installer_pubspec_part.dart`
- `lib/src/registry/registry_file.dart`
- `lib/src/registry/components_schema_validator.dart`
- `test/init_action_engine_test.dart`
- `test/installer_test.dart`

**Tests to add/run**

- Add tests for exact asset pubspec entries, preserve-existing behavior, overwrite behavior, and merge-strategy rejection on binary assets.
- Run: `dart test test/init_action_engine_test.dart test/installer_test.dart --reporter=expanded`
- Run: `dart analyze`

**Branch name suggestion**

- `branch-v1-gap-19-asset-semantics`

## Task 11: Post-Install Notes As Tracked Manual Work (GAP-23)

**Problem**

`Component.postInstall` exists and dry-run/installer can print notes, but notes are transient. Required manual steps are not modeled, tracked, or surfaced by doctor.

**How To Solve**

Promote post-install notes into a structured manifest field and lockfile record. Display them after install, include them in dry-run, and have doctor report unresolved required manual steps.

**What To Do**

- [ ] Support both legacy `postInstall: List<String>` and structured `postInstall: { notes, requiredManualSteps }`.
- [ ] Store post-install notes and required flag in the lockfile component record.
- [ ] Print notes after successful install and sync.
- [ ] Add `doctor` output for required manual steps.
- [ ] Treat legacy list-style manifests as `requiredManualSteps: false`.

**Edge Cases To Resolve**

- Empty notes with `requiredManualSteps: true` should fail schema/preflight.
- Duplicate notes from dependencies should be de-duplicated in output but retained per owning component in the lockfile.
- Non-interactive mode should still print required steps.

**Files likely touched**

- `lib/src/registry/component.dart`
- `lib/src/application/services/installer/installer.dart`
- `lib/src/application/services/installer/installer_dry_run_part.dart`
- `lib/src/application/services/lockfile/shadcn_lock.dart`
- `lib/src/presentation/cli/commands/doctor_command.dart`
- `test/installer_test.dart`
- `test/cli_integration_test.dart`

**Tests to add/run**

- Add tests for legacy list parsing, structured parsing, install output, dry-run output, lockfile persistence, and doctor warnings.
- Run: `dart test test/installer_test.dart test/cli_integration_test.dart --concurrency=1 --reporter=expanded`
- Run: `dart analyze`

**Branch name suggestion**

- `branch-v1-gap-23-post-install-tracking`

## Task 12: Explicitly Reject Undesigned Config Patches (GAP-24)

**Problem**

The original analysis flagged `config patches` as a placeholder. Current v1 has platform instructions and pubspec actions, but no safe general-purpose code patch contract.

**How To Solve**

Make v1 intentionally reject unsupported config patch declarations during preflight. Keep existing supported platform/pubspec actions. Document arbitrary code/config patching as out of scope until a separate patch format, dry-run diff, and rollback policy exists.

**What To Do**

- [ ] Add schema/preflight rejection for unsupported fields such as `configPatches`, `patches`, `mainDartPatch`, or generic `modifyFile` action types.
- [ ] Keep existing `platform` sections and `mergePubspec` init action supported.
- [ ] Ensure rejection happens before any file write.
- [ ] Add docs stating v1 does not support arbitrary config/code patches.

**Edge Cases To Resolve**

- Unknown fields already allowed by compatibility should be rejected only when they imply write/patch behavior.
- Future init action types must fail unless `init.version` is incremented and supported.
- A registry containing unsupported patches for a component not being installed should not block unrelated components unless schema validation loads the whole manifest strictly.

**Files likely touched**

- `lib/src/registry/components_schema_validator.dart`
- `lib/src/application/services/registry_manifest_preflight.dart`
- `lib/src/application/services/init_action_engine/init_action_engine.dart`
- `docs/developer/registry-directory-testing.md`
- `docs/reference/inline-init-actions.md`
- `test/schema_validation_test.dart`
- `test/init_action_engine_test.dart`

**Tests to add/run**

- Add tests proving unsupported patch declarations fail with zero writes.
- Add tests proving supported `platform` and `mergePubspec` still work.
- Run: `dart test test/schema_validation_test.dart test/init_action_engine_test.dart --reporter=expanded`
- Run: `dart analyze`

**Branch name suggestion**

- `branch-v1-gap-24-reject-config-patches`

## Task 13: Namespace Collision Detection For Manifest-Owned Namespaces (GAP-25)

**Problem**

Registry namespaces are unique only by convention. The CLI resolves command namespaces, but manifest-owned namespaces for future locale keys, generated symbols, and component metadata can collide silently if registries claim the same logical namespace.

**How To Solve**

Add install-time collision checks using registry namespace, component ID, and explicit manifest namespace fields introduced by the lock/manifest source-of-truth task. For v1, reject collisions that would cause the same generated target, manifest key, asset path, or future locale namespace to be owned by multiple qualified components.

**What To Do**

- [ ] Add `NamespaceCollisionPolicy` that compares pending install records against lockfile records.
- [ ] Detect duplicate qualified install target ownership, duplicate asset ownership, duplicate post-install namespace identifiers, and reserved locale namespace placeholders.
- [ ] Warn or fail before writes; fail for any collision that would overwrite owned files or keys.
- [ ] Document convention: registry-owned keys should use `<registryId>.<componentId>.<key>`.
- [ ] Leave detailed locale key collision semantics to Task 2, but reserve lockfile fields needed by that task.

**Edge Cases To Resolve**

- Reinstalling the same qualified component should update its own ownership record, not collide with itself.
- Two components may both depend on the same shared file only when lockfile ownership marks it as shared/reference-counted.
- Existing unqualified legacy records should migrate to the default namespace before collision checks.
- Different registries may install the same file name under different install roots without collision.

**Files likely touched**

- `lib/src/application/services/lockfile/shadcn_lock.dart`
- New: `lib/src/application/services/namespace_collision_policy.dart`
- `lib/src/application/services/installer/installer_manifest_part.dart`
- `lib/src/application/services/multi_registry/multi_registry_add_part.dart`
- `test/installer_test.dart`
- `test/cli_integration_test.dart`

**Tests to add/run**

- Add collision tests for duplicate targets across registries, shared ownership, and legacy migration.
- Add no-collision tests for same component name under separate install roots.
- Run: `dart test test/installer_test.dart test/cli_integration_test.dart --concurrency=1 --reporter=expanded`
- Run: `dart analyze`

**Branch name suggestion**

- `branch-v1-gap-25-namespace-collisions`

## Delivery Order

1. Task 1: trust policy.
2. Task 2: install target policy.
3. Task 3: manifest preflight/version guard.
4. Task 4: transaction coordinator.
5. Task 5: qualified installed identity.
6. Task 7: lockfile and manifest source of truth.
7. Task 8: pubspec conflict policy.
8. Task 9: dependency graph cycle detection.
9. Task 10: asset semantics.
10. Task 11: post-install tracking.
11. Task 12: reject unsupported config patches.
12. Task 13: namespace collision policy.
13. Task 6: derived capability cleanup can run after Task 3 or in parallel with Tasks 10-13 because it is mostly display/orchestration policy.

## Verification Gates

- Run after each task: `dart analyze`
- Run focused tests listed in the task.
- Run before merging the whole remediation set:
  - `dart test test/resolver_v1_test.dart test/config_state_migration_test.dart test/registry_directory_test.dart test/init_action_engine_test.dart test/multi_registry_manager_test.dart test/e2e_multi_registry_fixture_test.dart --reporter=expanded`
  - `dart test test/cli_integration_test.dart --concurrency=1 --reporter=expanded`
  - `dart test`

## Locale And Manifest Source-Of-Truth Note For Task 2

This plan intentionally references locale and manifest ownership only at boundaries:

- Task 7 reserves lockfile fields for locale key ownership.
- Task 13 reserves namespace collision hooks for locale key namespaces.
- Task 2 must define detailed locale source-of-truth, ARB/JSON behavior, `l10n.yaml` resolution, optional locale warnings, and locale update/remove semantics before any locale merge implementation is added.
