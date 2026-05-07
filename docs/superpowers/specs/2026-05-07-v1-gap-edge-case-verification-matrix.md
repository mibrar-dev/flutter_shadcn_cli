# V1 Gap Edge-Case Verification Matrix

## Purpose

Turn real or partial gaps from the v1 gap analysis and the v1 locale/component-manifest source-of-truth spec into concrete automated and manual verification cases.

This matrix is for implementation workers. It names the behavior to verify, existing test files to extend where possible, negative cases, no-write assertions, and the expected failure-message shape. Do not use it as permission to guess missing product behavior; unresolved rows must be resolved in implementation specs before code changes.

## Coverage Map

| Gap or spec area | Matrix section |
| --- | --- |
| GAP-01 | Path safety and no-write guards |
| GAP-02 | Registry trust and remote URL policy |
| GAP-03 | Install target scope policy |
| GAP-04 guard | Manifest schema version guards |
| GAP-05 | Manifest validation preflight |
| GAP-06 | Transactional add/init and dry-run |
| GAP-07 | Qualified component identity and ambiguity |
| GAP-09 | Manifest data as install authority |
| GAP-10 | Remove, update, and ownership behavior |
| GAP-14 | Lockfile/source ownership records |
| GAP-15 | Pubspec conflict and dependency ownership |
| GAP-17 | Dependency graph cycle detection |
| GAP-18 | Component version pinning |
| GAP-19 | Asset copy and pubspec semantics |
| GAP-21 | Sync reproducibility |
| GAP-22 | Doctor integrity checks |
| GAP-23 | Post-install notes tracking |
| GAP-24 | Unsupported config patch rejection |
| GAP-25 | Namespace and ownership collision detection |
| Locale source-of-truth | Locale matrix |
| Manifest source-of-truth | Per-component manifest resolution and cache invalidation matrix |

## Path Safety And No-Write Guards

- Problem
  - Registry and inline init writes must never escape the project root or approved target roots.
  - Invalid input must fail before project files, `.shadcn/state.json`, `.shadcn/config.json`, component manifests, pubspec, lockfile, or cache files are written.
- How To Verify
  - Create temp projects with sentinel files inside and outside the project root.
  - Run `init`, `add`, and `dry-run` with malicious `source`, `destination`, `target`, inline action paths, symlinks, absolute paths, URL fragments, and backslashes.
  - Assert sentinel files are unchanged and no new files appear outside the project root.
- Automated Tests To Add
  - `test/resolver_v1_test.dart`: reject `..`, leading slash, backslash, `?`, `#`, empty segments, and symlink escapes.
  - `test/init_action_engine_test.dart`: reject unsafe `copyFile`, `copyDir`, and pubspec-derived asset paths with zero writes.
  - `test/installer_test.dart`: reject component files, shared files, assets, platform files, and locale destinations that escape policy.
  - `test/e2e_multi_registry_fixture_test.dart`: verify unsafe remote/local registry manifests abort before any install artifact is created.
- Manual Checks
  - Follow `docs/reference/manual-testing-guide.md` with a local registry fixture that attempts to write `../outside.dart`, `/tmp/outside.dart`, `.git/config`, `.shadcn/state.json`, and `pubspec.yaml` as component files.
  - Verify `flutter_shadcn doctor` still runs after failed attempts and does not report partially installed components.
- Edge Cases To Resolve
  - Absolute paths that normalize inside the project root still require target-scope policy checks.
  - Symlinked existing parent directories must not allow writes outside the project.
  - Inline init actions remain project-root-relative but must use the same path guard.
  - Source paths are registry-root-relative only and must never be treated as arbitrary URLs.
- Expected Failure Message Shape
  - `Unsafe path in <field>: <path>. Paths must be project-relative, must not contain traversal, and must stay within <allowed root>. No files were written.`

## Registry Trust And Remote URL Policy

- Problem
  - Remote registry data must not be fetched or installed from untrusted or non-HTTPS sources.
  - Local development registries must remain usable without being misclassified as remote URLs.
- How To Verify
  - Exercise directory loading, `init <namespace>`, `add`, `info`, `dry-run`, and cached/offline resolution against HTTPS, HTTP, file-backed, local absolute path, missing trust, invalid trust mode, empty hash, and `--skip-integrity` cases.
  - Assert rejected remote registries fail before install-source resolution performs writes.
- Automated Tests To Add
  - `test/registry_directory_test.dart`: HTTPS required, HTTP rejected, invalid trust metadata rejected, local paths accepted.
  - `test/cli_integration_test.dart`: `init <namespace>` and `add @namespace/component` reject untrusted remote registries with no project writes.
  - `test/multi_registry_manager_test.dart`: offline cache may be used only for previously trusted registries.
- Manual Checks
  - Run local fixture commands with `--registries-path` and `--registry-path`; confirm local paths work.
  - Run a fixture registry entry with `http://` base URL; confirm it fails before `.shadcn/components/` changes.
- Edge Cases To Resolve
  - GitHub tree/raw normalization must remain HTTPS.
  - `--skip-integrity` may bypass developer hash checks only; it must not bypass HTTPS, path safety, or schema validation.
  - Cached data from an untrusted remote must not become trusted by being present on disk.
- Expected Failure Message Shape
  - `Registry <namespace> is not trusted: <reason>. Remote registries must use HTTPS and explicit trust metadata. No files were written.`

## Install Target Scope Policy

- Problem
  - Safe project-relative paths can still overwrite broad in-project files unless component install roots are enforced.
- How To Verify
  - Install components from two namespaces with default and custom install roots.
  - Attempt writes to `lib/main.dart`, `lib/components/<otherNamespace>/...`, `.shadcn/...`, `.git/...`, `test/...`, and allowed asset paths.
- Automated Tests To Add
  - `test/installer_test.dart`: allow namespace install root, shared root, and explicit `assets/<namespace>/...`; reject broad project targets.
  - `test/e2e_multi_registry_fixture_test.dart`: preserve existing single-registry default roots while enforcing per-registry scope.
- Manual Checks
  - In a real app, install a valid local component and verify files land under configured roots.
  - Try a fixture component targeting `lib/main.dart`; confirm failure and unchanged app file.
- Edge Cases To Resolve
  - Generated aliases and CLI-managed manifests are first-party writes; registry component target policy should not block them.
  - Existing user files skipped by preserve behavior must not be recorded as installed by the registry.
  - Assets and fonts need explicit path ownership for later pubspec/remove behavior.
- Expected Failure Message Shape
  - `Install target outside allowed scope for <namespace>/<component>: <destination>. Allowed roots: <roots>. No files were written.`

## Manifest Schema Version Guards

- Problem
  - Unsupported registry directory or explicit component manifest versions must fail before writes.
  - Missing legacy component schema compatibility can remain only where the implementation spec explicitly preserves it.
- How To Verify
  - Feed `schemaVersion` values `0`, `1`, `"1"`, `2`, missing, null, and malformed JSON through directory, components, and per-component manifest loading.
  - Assert the first writeable command aborts before creating or modifying project files.
- Automated Tests To Add
  - `test/schema_validation_test.dart`: collect all schema/version failures and assert zero-write preflight.
  - `test/registry_directory_test.dart`: directory `schemaVersion != 1` fails even if other fields look valid.
  - `test/cli_integration_test.dart`: invalid explicit component schema fails for `add`, `dry-run`, `assets`, and preload installs.
- Manual Checks
  - Run `flutter_shadcn init <namespace>` against a directory fixture with `schemaVersion: 2`.
  - Confirm `init <namespace>` with inline actions does not fetch `meta.json`.
- Edge Cases To Resolve
  - Offline cached invalid manifests must still fail validation.
  - JSON decode failures must be distinct from schema incompatibility.
  - `init <namespace>` without inline actions validates `registries.json` but must not require `components.json`.
- Expected Failure Message Shape
  - `Unsupported <manifest kind> schemaVersion <value>; supported version is 1. No files were written.`

## Manifest Validation Preflight

- Problem
  - Invalid manifest shape must not fail mid-install after partial writes.
- How To Verify
  - Use invalid field types, missing required fields, invalid merge strategies, manifest id mismatch, incomplete install metadata, and invalid hashes.
  - Assert all validation errors are reported together and no install/cache/lockfile writes occur.
- Automated Tests To Add
  - `test/schema_validation_test.dart`: missing `target`/`destination`, null `source`, wrong `files` type, invalid `postInstall`, unsupported patches.
  - `test/cli_integration_test.dart`: command-level preflight failure leaves `.shadcn/`, `pubspec.yaml`, and component targets unchanged.
  - `test/registry_directory_test.dart`: directory validation remains fatal before registry resolution.
- Manual Checks
  - Run `flutter_shadcn validate --json` on invalid local registry fixtures and confirm structured error output.
  - Run `flutter_shadcn add @namespace/button` against the same fixture and confirm no project change.
- Edge Cases To Resolve
  - Per-component manifest `id` must equal requested component id.
  - `index.json` entries with search-only metadata are not install sources.
  - Transient network failures must not be recorded as negative manifest support.
- Expected Failure Message Shape
  - `Invalid manifest for <namespace>/<component>: <N> validation error(s): <field>: <reason>. No files were written.`

## Transactional Add, Init, And Dry-Run

- Problem
  - Failed add/init operations must restore file, pubspec, state, manifest, alias, lockfile, cache, and locale changes.
  - Dry-run must remain read-only and must not persist capability cache mutations.
- How To Verify
  - Inject failures after file copy, pubspec edit, manifest write, locale write, lockfile write, and cache write.
  - Snapshot the temp project before the command and compare all files after failure.
- Automated Tests To Add
  - `test/installer_test.dart`: rollback copied files, overwritten files, aliases, component manifests, lockfile, state, and pubspec.
  - `test/init_action_engine_test.dart`: rollback inline copied files and pubspec deltas.
  - `test/cli_integration_test.dart`: `dry-run` prints planned writes but produces no project or cache writes.
- Manual Checks
  - Run `flutter_shadcn dry-run @shadcn/button`; compare `git status --short` before and after.
  - Simulate a read-only target directory and confirm rollback report keeps the original error visible.
- Edge Cases To Resolve
  - Existing files skipped because overwrite is false must not be deleted during rollback.
  - Rollback failures must be reported without hiding the original install error.
  - Cache writes are command side effects; dry-run must discard them.
- Expected Failure Message Shape
  - `Install failed for <namespace>/<component>: <cause>. Rolled back <N> change(s). <rollback failure summary if any>.`

## Qualified Component Identity And Ambiguity

- Problem
  - Bare component IDs are ambiguous across enabled registries and installed records must be keyed by namespace plus component id.
- How To Verify
  - Create two enabled registries with `button`.
  - Test `add button`, `add @a/button`, `add @b/button`, `remove button`, `remove @a/button`, `sync`, `doctor`, `list`, and `dry-run`.
- Automated Tests To Add
  - `test/add_resolution_service_test.dart`: qualified parsing, unique bare resolution, ambiguous bare rejection, suggestions.
  - `test/component_address_command_test.dart`: accepted user-facing address forms.
  - `test/config_state_migration_test.dart`: legacy bare manifests migrate to the default namespace.
  - `test/cli_integration_test.dart`: two installed `button` components do not overwrite each other's manifests.
- Manual Checks
  - In a fixture app, install `@a/button` and `@b/button`; inspect `.shadcn/components/` and command output.
- Edge Cases To Resolve
  - Qualified request missing in target registry but present elsewhere fails for the requested namespace.
  - Existing single-registry projects can still use bare IDs when unique.
  - Error text must recommend `@namespace/component`.
- Expected Failure Message Shape
  - `Component "button" exists in multiple enabled registries: @a/button, @b/button. Use a qualified component address. No files were written.`

## Manifest Data As Install Authority

- Problem
  - Registry-level capability flags must not decide install behavior when component data says otherwise.
- How To Verify
  - Use a registry whose advertised capabilities are false/stale but component data declares shared groups, assets, locale resources, or pubspec changes.
  - Use another registry whose capabilities are true but component data has none.
- Automated Tests To Add
  - `test/multi_registry_manager_test.dart`: install decisions derive from component/shared/pubspec/asset declarations.
  - `test/cli_integration_test.dart`: stale false capabilities do not suppress required shared install.
  - `test/registry_directory_test.dart`: advertised capabilities remain display metadata.
- Manual Checks
  - Run `flutter_shadcn registries` or equivalent listing and confirm advertised metadata is not presented as install authority.
- Edge Cases To Resolve
  - Lightweight list/search must not fetch every manifest just to derive capabilities.
  - Existing config files with capability fields must still deserialize.
- Expected Failure Message Shape
  - `Manifest for <namespace>/<component> is incomplete: <missing install metadata>. Capability flags are informational and cannot supply install metadata.`

## Remove, Update, And Ownership Behavior

- Problem
  - Remove/update must act only on recorded ownership; they must not guess files, locale resources, or dependencies from a current registry response.
- How To Verify
  - Install components with shared files, shared dependencies, assets, locale resources, and post-install notes.
  - Remove one owner while another owner remains.
  - Update one component where the registry has changed files and locale metadata.
- Automated Tests To Add
  - `test/installer_test.dart`: remove owned files only, preserve shared references, update owned files transactionally.
  - `test/cli_integration_test.dart`: missing installed component manifest prevents guessed deletion.
  - `test/e2e_multi_registry_fixture_test.dart`: cross-registry same component id removal targets only the qualified record.
- Manual Checks
  - After `remove @namespace/component`, inspect copied files, `.shadcn/state.json.managedDependencies`, and owned locale files.
- Edge Cases To Resolve
  - Missing installed manifest: report unverifiable ownership and do not delete guessed locale/files.
  - User-modified files need the update contract decided before overwrite behavior is implemented.
  - Dependency removal must be reference-counted.
- Expected Failure Message Shape
  - `Cannot remove <namespace>/<component> safely: ownership record is missing or incomplete. No unowned files were deleted.`

## Lockfile And Source Ownership Records

- Problem
  - Reproducible installs, sync, doctor, version pinning, locale ownership, dependency ownership, and post-install tracking require a durable source-of-truth record.
- How To Verify
  - Install components from per-component manifest, `components.json`, and complete `index.json`.
  - Inspect lockfile/component manifest records for namespace, component id, version, source hash, manifest source, installed files, assets, pubspec ownership, post-install notes, and locale ownership placeholders/resources.
- Automated Tests To Add
  - `test/installer_test.dart`: lockfile write participates in the install transaction.
  - `test/config_state_migration_test.dart`: legacy `.shadcn/components/<id>.json` records synthesize qualified lock records without guessed versions.
  - `test/cli_integration_test.dart`: `.shadcn/state.json.managedDependencies` behavior remains intact after lockfile writes.
- Manual Checks
  - Install a component and inspect `shadcn.lock`, `.shadcn/components/`, and `.shadcn/state.json`.
- Edge Cases To Resolve
  - Missing version in legacy records is stored as `null` or `unknown`, not guessed.
  - Lockfile write failure rolls back all previous writes.
  - Two registries with the same component ID produce separate records.
- Expected Failure Message Shape
  - `Failed to write ownership record for <namespace>/<component>: <cause>. Rolled back install; project is unchanged.`

## Pubspec Conflict And Dependency Ownership

- Problem
  - Pubspec edits must not silently overwrite user constraints or remove shared dependencies still owned by another component.
- How To Verify
  - Test string constraints, same constraints, conflicting constraints, path/git/sdk/map dependencies, dev dependencies, comments, assets, fonts, and shared ownership.
- Automated Tests To Add
  - `test/installer_test.dart`: component pubspec planner add/keep/conflict/remove behavior.
  - `test/init_action_engine_test.dart`: inline `mergePubspec` preserves unrelated sections and comments where supported.
  - `test/cli_integration_test.dart`: non-interactive conflict fails with no writes.
- Manual Checks
  - Create a Flutter app with `intl: ^0.19.0`; install a component requiring `intl: ^0.20.0`; confirm the CLI does not silently overwrite.
- Edge Cases To Resolve
  - Map-shaped dependencies must not be serialized back as strings.
  - Dev dependencies change only when explicitly declared.
  - `.shadcn/state.json.managedDependencies` remains compatible while lockfile ownership is added.
- Expected Failure Message Shape
  - `Dependency conflict for <package>: project has <existing>, <namespace>/<component> requires <required>. Choose a resolution or abort. No files were written.`

## Dependency Graph Cycle Detection

- Problem
  - Component/shared dependency cycles must fail before installs instead of being skipped silently.
- How To Verify
  - Build graph fixtures for component cycles, shared cycles, self-cycles, component-to-shared cycles, missing dependencies, and acyclic dependency closures.
- Automated Tests To Add
  - `test/installer_test.dart`: cycle path reporting and no-write abort behavior.
  - `test/e2e_multi_registry_fixture_test.dart`: bulk add validates the full graph before any component writes.
- Manual Checks
  - Run a local registry fixture with `button -> form_control -> button`; confirm clear cycle output.
- Edge Cases To Resolve
  - Missing dependency is a different error than cycle.
  - Optional file dependencies do not create hard cycles unless required for install.
  - `dry-run` and `add` must share the same graph validation.
- Expected Failure Message Shape
  - `Dependency cycle detected: button -> form_control -> button. Resolve the registry manifest cycle before installing. No files were written.`

## Component Version Pinning

- Problem
  - Component versions must be parsed, installed, locked, synced, and updated deliberately.
- How To Verify
  - Test unversioned install, `@namespace/component@1.2.0`, unavailable version, invalid semver, legacy no-version manifests, and update planning.
- Automated Tests To Add
  - `test/add_resolution_service_test.dart`: parse and normalize qualified versioned refs.
  - `test/cli_parser_test.dart`: command accepts versioned refs without confusing namespace syntax.
  - `test/installer_test.dart`: lockfile records installed version and source hash.
  - `test/cli_integration_test.dart`: unavailable pinned version fails before writes.
- Manual Checks
  - Install a pinned version from a local registry with multiple versions; run sync and confirm the same version is used.
- Edge Cases To Resolve
  - Missing version in old manifests must not be guessed from registry current version.
  - Update must produce a plan/diff before transactional writes.
- Expected Failure Message Shape
  - `Version <version> of <namespace>/<component> is not available. Available versions: <versions>. No files were written.`

## Asset Copy And Pubspec Semantics

- Problem
  - Assets and fonts are copied artifacts, not mergeable structured documents; pubspec entries must reflect exact copied files unless another explicit contract is added.
- How To Verify
  - Test SVG, PNG, JPG, WebP, TTF, OTF, WOFF, WOFF2, existing assets, overwrite, preserve, invalid merge strategy, and exact pubspec entry behavior.
- Automated Tests To Add
  - `test/installer_test.dart`: reject deep merge strategies for asset/font extensions, preserve existing files, overwrite when explicit, record ownership.
  - `test/init_action_engine_test.dart`: inline copied assets update pubspec only for files actually written.
  - `test/schema_validation_test.dart`: invalid asset strategy rejected before writes.
- Manual Checks
  - Install a component with one SVG and one PNG; inspect `pubspec.yaml` for exact file paths and no broad directory entry unless explicitly declared by spec.
- Edge Cases To Resolve
  - SVG is text but non-merge for v1.
  - Existing asset preserved means it is not newly owned by the component unless ownership semantics explicitly say otherwise.
  - Binary hash mismatch fails before writing.
- Expected Failure Message Shape
  - `Unsupported asset strategy <strategy> for <destination>. Assets support copy or copy_preserve_user only. No files were written.`

## Sync Reproducibility

- Problem
  - `sync` must reproduce installed state from ownership records without relying on guessed latest registry data.
- How To Verify
  - Clone/copy a fixture project with lockfile and missing installed files.
  - Run sync online, offline with valid cache, offline with missing cache, and with stale/missing registry entries.
- Automated Tests To Add
  - `test/cli_integration_test.dart`: sync reinstalls locked namespace/component/version records.
  - `test/e2e_multi_registry_fixture_test.dart`: sync handles two registries and same component IDs.
  - `test/installer_test.dart`: sync preserves existing ownership records when registry source is unavailable.
- Manual Checks
  - Delete an installed component file, run `flutter_shadcn sync`, and verify the exact locked component is restored.
- Edge Cases To Resolve
  - Offline sync uses only cached data that matches the lock/source hash.
  - Missing cache fails clearly and leaves current files unchanged.
  - Components committed to repo versus restored by sync remains a workflow decision to document.
- Expected Failure Message Shape
  - `Cannot sync <namespace>/<component>@<version>: required cached manifest/source is missing. No files were written.`

## Doctor Integrity Checks

- Problem
  - `doctor` must surface drift, missing ownership, missing dependencies, missing locale resources, stale caches, and unresolved manual steps.
- How To Verify
  - Create installed records, then delete files, edit dependencies, remove locale files, add conflicting ownership, and stale cache entries.
- Automated Tests To Add
  - `test/cli_integration_test.dart`: doctor reports files, dependencies, component manifests, locale ownership, and post-install notes.
  - `test/installer_test.dart`: installed records contain enough data for doctor checks.
  - `test/command_matrix_test.dart`: doctor JSON/plain command forms remain registered.
- Manual Checks
  - Follow `docs/guides/diagnostics.md`; run `flutter_shadcn doctor`, `validate`, `audit`, and `deps` after deliberately breaking one owned file.
- Edge Cases To Resolve
  - Doctor reports problems but does not repair unless a separate command is invoked.
  - Missing optional locale resources should be warnings, not install failures retroactively.
  - Stale positive and negative manifest cache entries are reported per registry.
- Expected Failure Message Shape
  - `Doctor found <N> issue(s): <component/status/detail>. Run sync or reinstall after resolving configuration errors.`

## Post-Install Notes Tracking

- Problem
  - Manual steps must be displayed and persisted so doctor/sync can remind users when required steps remain.
- How To Verify
  - Test legacy list-style `postInstall`, structured `{ notes, requiredManualSteps }`, empty required notes, duplicate notes, dependencies with notes, install output, dry-run output, sync output, and doctor output.
- Automated Tests To Add
  - `test/installer_test.dart`: parse/store legacy and structured post-install metadata.
  - `test/cli_integration_test.dart`: install/dry-run/sync output includes notes; doctor reports required steps.
  - `test/schema_validation_test.dart`: empty notes with `requiredManualSteps: true` fail before writes.
- Manual Checks
  - Install a local component that declares a required manual step and verify the note appears after install and in doctor.
- Edge Cases To Resolve
  - Output may de-duplicate notes, but lockfile retains ownership per component.
  - Non-interactive mode still prints required manual steps.
- Expected Failure Message Shape
  - `Invalid postInstall for <namespace>/<component>: requiredManualSteps is true but notes are empty. No files were written.`

## Unsupported Config Patch Rejection

- Problem
  - Arbitrary code/config patch fields are not designed for v1 and must fail before writes.
- How To Verify
  - Test component manifests and inline init actions containing `configPatches`, `patches`, `mainDartPatch`, `modifyFile`, unknown write action types, and supported `platform`/`mergePubspec` controls.
- Automated Tests To Add
  - `test/schema_validation_test.dart`: unsupported patch declarations fail with zero writes.
  - `test/init_action_engine_test.dart`: unsupported init action types fail; supported `mergePubspec` still works.
  - `test/cli_integration_test.dart`: command-level failure leaves app files unchanged.
- Manual Checks
  - Run a local registry fixture that attempts to patch `lib/main.dart`; confirm the CLI rejects it and prints v1 scope guidance.
- Edge Cases To Resolve
  - Unknown passive metadata fields are not the same as unsupported write/patch behavior.
  - Unsupported patches for an unrelated component should not block installing a different component unless strict whole-manifest validation requires it.
- Expected Failure Message Shape
  - `Unsupported v1 patch declaration <field/action> in <namespace>/<component>. Arbitrary config/code patches are not supported. No files were written.`

## Namespace And Ownership Collision Detection

- Problem
  - Namespace uniqueness is convention-based; CLI must detect collisions that would overwrite owned files, assets, locale namespaces, or generated ownership keys.
- How To Verify
  - Install components from different registries claiming the same target, asset, locale namespace placeholder, post-install namespace, or shared file.
  - Reinstall the same qualified component and install two components with same component id under separate roots.
- Automated Tests To Add
  - `test/installer_test.dart`: duplicate target ownership fails, same-owner update allowed, shared/reference-counted ownership allowed.
  - `test/cli_integration_test.dart`: cross-registry collisions fail before writes.
  - `test/config_state_migration_test.dart`: legacy records migrate before collision checks.
- Manual Checks
  - Install `@a/button`, then attempt `@b/button` targeting the same owned file; confirm no overwrite.
- Edge Cases To Resolve
  - Same file can be shared only when lockfile ownership marks it as shared/reference-counted.
  - Different registries using separate install roots do not collide.
  - Locale key namespace collision details are owned by locale source-of-truth work.
- Expected Failure Message Shape
  - `Ownership collision for <path/key>: already owned by <owner>, requested by <namespace>/<component>. No files were written.`

## Per-Component Manifest Resolution Matrix

| Case | How To Verify | Automated Tests To Add | Expected Result |
| --- | --- | --- | --- |
| Per-component manifest exists and conflicts with `components.json` | Request `@namespace/button` where both sources exist with different file lists | `test/multi_registry_manager_test.dart`, `test/cli_integration_test.dart` | Per-component manifest wins; lock/installed manifest records `manifestSource: perComponent` |
| Registry does not advertise `paths.componentManifests` | Install twice from same registry | `test/registry_directory_test.dart`, `test/e2e_multi_registry_fixture_test.dart` | First command records registry-level negative support; second command skips guessed manifest probes |
| Per-component manifest 404 for one component | Install `button`, then install `card` from same registry | `test/multi_registry_manager_test.dart` | Component-level miss recorded only for `button`; `card` still probes manifest |
| Per-component manifest fetch timeout/5xx | Force transient failure with fallback available | `test/cli_integration_test.dart` | No negative cache/miss recorded; valid fallback may be used only by cache rules |
| Registry-level negative support | Resolve two components after negative cache | `test/multi_registry_manager_test.dart` | Skip all per-component probes for same namespace/source hash until invalidation or refresh |
| Component-level miss | Resolve same component twice and a different component once | `test/multi_registry_manager_test.dart` | Same component skips probe; different component probes |
| Incomplete `index.json` only | Registry lacks manifest and components data | `test/schema_validation_test.dart`, `test/cli_integration_test.dart` | Install fails before writes |
| Complete `index.json` fallback | Registry has no manifest/components but complete install entry | `test/e2e_multi_registry_fixture_test.dart` | Install succeeds and records `manifestSource: indexJson` |
| Manifest id mismatch | Request `button`, manifest says `card` | `test/schema_validation_test.dart` | Fail and do not fall back silently |
| Qualified miss but exists elsewhere | Request `@a/button`, only `@b/button` exists | `test/add_resolution_service_test.dart`, `test/cli_integration_test.dart` | Fail for `@a/button`; optional suggestion may name `@b/button` if known |

Expected failure message shape: `Cannot resolve install metadata for <namespace>/<component>: <reason>. The CLI requires per-component manifest, components.json, or complete index.json metadata. No files were written.`

## Cache Invalidation Matrix

| Cache case | Positive/negative requirement | Component-level miss requirement | Offline requirement | Refresh requirement | Automated Tests To Add |
| --- | --- | --- | --- | --- | --- |
| Positive support cache hit | Use cached support for same namespace/source hash | Existing misses still scoped by component id | Use cached manifest body only if present and valid | `--refresh` bypasses and revalidates | `test/multi_registry_manager_test.dart`, `test/cli_integration_test.dart` |
| Negative support cache hit | Skip per-component probes for same namespace/source hash | Misses are irrelevant while registry negative applies | Use cached `components.json`, then complete `index.json` | `--refresh` clears negative before probing | `test/registry_directory_test.dart`, `test/e2e_multi_registry_fixture_test.dart` |
| Component-level miss | Do not mark registry negative | Skip probe only for the same component id/source hash | Do not create or update miss while offline | Refresh clears or ignores miss for affected registry | `test/multi_registry_manager_test.dart` |
| Different component after miss | Registry may still support manifests | Probe different component id | Use cached body if available; otherwise fallback | Refresh probes online | `test/multi_registry_manager_test.dart` |
| Source hash changes | Ignore old positive/negative/miss entries | Old misses do not apply | Offline cannot use old entry as current support | Online refresh creates new entry | `test/registry_directory_test.dart` |
| ETag changes | Invalidate affected entry | Invalidate misses tied to old source hash/ETag | Offline cannot observe ETag changes | Refresh revalidates | `test/registry_directory_test.dart` |
| `baseUrl`, local root, component manifest template, `componentsPath`, or `indexPath` changes | Invalidate affected entry | Invalidate misses tied to old source | Offline uses only matching cached source | Refresh revalidates | `test/registry_directory_test.dart` |
| Unknown support offline | Do not probe network and do not mark negative | Do not create misses | Try cached per-component body, cached `components.json`, then cached complete `index.json`; fail if absent/incomplete | Not applicable offline | `test/cli_integration_test.dart` |
| Cache miss offline | No support state available | No miss state available | Fail with cache-missing error and no writes | Not applicable offline | `test/cli_integration_test.dart` |
| Dry-run cache side effects | May read cache/network for planning | Does not persist misses | Does not persist offline-derived state | With refresh, bypasses stale cache but discards mutations | `test/cli_integration_test.dart` |

Expected failure message shape: `Offline cache miss for <namespace>/<component>: required <manifest source> is not cached for source <hash>. No files were written.`

## Locale Matrix

| Locale case | How To Verify | Automated Tests To Add | Expected Result |
| --- | --- | --- | --- |
| Missing `l10n.yaml` | Install locale-aware component in project without `l10n.yaml` | `test/installer_test.dart`, `test/cli_integration_test.dart` | Fail before files/pubspec/state/cache writes with `flutter_shadcn locale init` guidance |
| `flutter_shadcn locale init` | Run in project without `l10n.yaml` | `test/cli_integration_test.dart`, `test/command_matrix_test.dart` | Creates default `l10n.yaml` and `lib/l10n/`; refuses to overwrite existing file |
| Invalid `arb-dir` missing/empty | Existing `l10n.yaml` lacks `arb-dir` | `test/installer_test.dart`, `test/cli_integration_test.dart` | Fail before writes |
| Invalid `arb-dir` escaping root | `arb-dir: ../outside` or symlink escape | `test/resolver_v1_test.dart`, `test/installer_test.dart` | Reject through project path guard |
| Missing `template-arb-file` for ARB | Install ARB resource with incomplete `l10n.yaml` | `test/installer_test.dart`, `test/cli_integration_test.dart` | Install fails; doctor reports config issue |
| Missing `output-localization-file` for ARB | Install ARB resource with incomplete `l10n.yaml` | `test/installer_test.dart`, `test/cli_integration_test.dart` | Install fails; doctor reports config issue |
| ARB metadata preservation | Source ARB has `@key`, placeholders, examples, custom metadata | `test/installer_test.dart` | Metadata copied exactly with message key; no placeholder rewriting |
| Malformed ARB JSON | Source ARB invalid JSON | `test/schema_validation_test.dart`, `test/installer_test.dart` | Fail before writes |
| JSON locale object requirement | Source JSON is array, scalar, or null | `test/schema_validation_test.dart`, `test/installer_test.dart` | Fail before writes |
| Locale selection from project | Existing ARB files identify supported locales | `test/installer_test.dart` | Install only selected project locales |
| Locale selection from config | `.shadcn/config.json.locale.supportedLocales` set | `test/config_state_migration_test.dart`, `test/installer_test.dart` | Config locales used when project locales cannot be derived |
| Locale selection from registry default | No project/config selection | `test/installer_test.dart` | Install only registry default locale |
| No silent all-locale install | Registry publishes five locales, project selects two | `test/installer_test.dart`, `test/cli_integration_test.dart` | Only two selected locales installed; output names skipped locales where required by spec |
| Explicit `--locale` selected and published | Repeatable flag selects subset | `test/cli_parser_test.dart`, `test/cli_integration_test.dart` | Only selected published locales installed |
| Explicit `--locale` not published | Install with missing selected locale | `test/cli_integration_test.dart` | Dry-run may plan/report; install fails for required selected locale or warns for optional selected locale |
| Required selected locale missing | Manifest lacks selected required locale | `test/installer_test.dart` | Fail before writes |
| Optional selected locale missing | Manifest lacks selected optional locale | `test/installer_test.dart`, `test/cli_integration_test.dart` | Warn and continue |
| Required registry locale not selected | Registry marks locale required but project selects another locale | `test/installer_test.dart` | Warn and continue, naming selection source |
| No matched locale resources | Component declares locale resources but none match selection | `test/installer_test.dart` | Fail unless only optional locales were requested |
| Locale ownership on add | Install locale resources | `test/installer_test.dart`, `test/cli_integration_test.dart` | Installed component manifest records `resourcesInstalled`, `selectionSource`, `registryNamespace`, `registrySourceHash`, and `manifestSource` |
| Locale ownership on remove | Remove component with owned locale file shared/not shared | `test/installer_test.dart` | Delete only files owned solely by removed component |
| Locale ownership on sync | Sync installed component with recorded locale ownership | `test/cli_integration_test.dart` | Update only owned locale resources |
| Locale ownership on doctor | Delete or conflict installed locale files | `test/cli_integration_test.dart` | Doctor reports missing/conflicting locale ownership |

Expected failure message shape: `Locale resources for <namespace>/<component> require valid l10n.yaml: <specific field/error>. Run flutter_shadcn locale init or fix l10n.yaml. No files were written.`

## Branch And Commit Checklist

Each implementation task branch must complete this checklist before handoff:

- Run the focused tests named in that task's implementation plan and any matrix tests touched by the change.
- Run `dart analyze` and record the result. If the isolated worktree analyzer fails for existing package/import reasons, record the exact failure category and do not hide it.
- Run `git status --short` and verify the write set is limited to the task scope.
- Commit the task branch with a focused message.
- Push the task branch to origin.
- Report:
  - branch name
  - focused test commands and results
  - `dart analyze` result
  - files changed
  - commit SHA
  - push status
  - unresolved edge cases or follow-up specs required
