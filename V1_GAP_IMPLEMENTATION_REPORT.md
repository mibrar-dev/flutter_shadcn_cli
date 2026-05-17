# v1 Gap Implementation Report

Date: 2026-05-07

## Current Status

The full v1 migration is not finished yet.

Completed and pushed:

1. Resolver and filesystem safety utilities.
2. Config/state migration and locale v1 support.
3. Registry directory fetch, schema validation, manifest preflight, and manifest cache behavior.
4. Transactional rollback for failed component installs and inline init actions.

Still pending:

5. Wire remaining `init` and `add` surfaces to the new engine and add focused tests.
6. End-to-end fixture tests for the full v1 flow.

## Completed Branches

| Task | Branch | Commit | Status |
| --- | --- | --- | --- |
| Trust policy and remote integrity hardening | `branch-v1-gap-02-trust-policy` | `3f39035` | Pushed |
| Install destination scope and path safety | `branch-v1-gap-01-03-install-scope` | `5155be2` | Pushed |
| Manifest preflight, schema validation, and cache behavior | `branch-v1-gap-04-05-manifest-preflight` | `9d9cacd` | Pushed |
| Transactional failed-install rollback | `branch-v1-gap-06-install-transactions` | `32f5dcd` | Pushed |

## Before vs Now

### Trust Policy and Remote Integrity

Before:

- Remote registries could be used without a clear trust boundary.
- Integrity checks and remote source rules were not consistently separated.
- Developer bypass behavior risked weakening runtime trust checks.

Now:

- Remote registry usage is constrained by `RegistryTrustPolicy`.
- Remote registry metadata includes sha256 trust metadata.
- `--skip-integrity` does not bypass trust policy.
- HTTPS and non-loopback remote rules are enforced where applicable.

### Install Destination Scope

Before:

- Component and shared file destinations were not scoped tightly enough.
- Registry entries could target reserved project files too broadly.
- Asset/font paths had weaker validation for malformed or unsafe paths.

Now:

- `InstallTargetPolicy` limits component and shared writes to allowed destinations.
- Reserved project files are rejected for registry component writes.
- Assets and font paths are guarded, including control-character edge cases.
- Dependency file installation follows the same safety policy.

### Manifest Preflight and Cache Behavior

Before:

- Registry data could be cached before validation succeeded.
- Some validation and integrity failures could fall back to stale cache.
- Component/theme data could be loaded during namespace init even when no inline init existed.

Now:

- Registry directory and component payloads validate before cache writes.
- Validation and integrity failures do not silently fall back to stale cache.
- Registry directory and components schema versions are guarded.
- Malformed JSON errors are clearer.
- Namespace init without inline actions avoids unnecessary component/theme loading.

### Transactional Install and Init Rollback

Before:

- A failed `add` could leave partially-written component files.
- Failed installs could leave per-component manifests, state, aliases, platform files, or pubspec changes behind.
- Inline init actions only had explicit recorded rollback, not automatic rollback on mid-run failure.
- Bulk install finalizers could flush pending dependencies/manifests even after the main action failed.

Now:

- `InstallTransaction` snapshots files before mutation and tracks created directories.
- `addComponent` and `runBulkInstall` share one transaction across nested component/shared installs.
- Failed installs restore overwritten files, delete newly-created files, restore pubspec, and remove empty created directories.
- Per-component manifests, aggregate manifests, state writes, aliases, platform writes, assets, fonts, and dependency updates are covered.
- Inline `InitActionEngine.executeActions` automatically rolls back copied files, created dirs, and pubspec changes if a later action fails.
- Existing `rollbackRecordedChanges` remains intact.
- Installer caches are reset after transaction rollback so a long-lived installer does not believe rolled-back files are installed.

## Verification Completed

Task 4 latest verification:

- `dart analyze`
- `dart test test/installer_test.dart test/init_action_engine_test.dart --reporter=expanded`
- `git diff --check`
- `graphify update .`
- Subagent review: approved, no findings.

Earlier task branches also passed focused tests and static analysis before push.

## Known Remaining Work

The remaining implementation work is not just documentation. The next steps are:

1. Wire any remaining public `init` and `add` command surfaces to the new v1 engine consistently.
2. Add focused tests for those command surfaces.
3. Run and fix end-to-end fixture tests for the full v1 multi-registry flow.
4. Reconcile known broad-test failures that were previously identified around default offline registry-directory lookup before local overrides.
5. Produce a final completion report only after Tasks 5 and 6 are green and pushed.
