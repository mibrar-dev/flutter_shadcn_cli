# GAP-25 Namespace Collision Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reject install-time namespace and ownership collisions before component writes.

**Architecture:** Add a focused `NamespaceCollisionPolicy` that validates pending `ShadcnLockComponent` records against existing lockfile components. Extend lockfile component records with explicit ownership lists for asset paths, manifest keys, post-install namespaces, and reserved locale namespaces while preserving legacy load compatibility.

**Tech Stack:** Dart CLI, `package:test`, existing installer lockfile repository.

---

### Task 1: Failing Installer Coverage

**Files:**
- Modify: `test/installer_test.dart`

- [ ] **Step 1: Add tests**

Add tests that:
- seed `shadcn.lock` with `@other/card` owning `lib/ui/shared/generated.dart`, then assert installing `@shadcn/button` fails before writing the file;
- seed asset, manifest key, post-install namespace, and locale namespace ownership collisions and assert install fails;
- seed the same ownership on `@shadcn/button` and assert reinstall/upsert is allowed.

- [ ] **Step 2: Verify red**

Run: `dart test test/installer_test.dart --reporter=expanded`

Expected: failures because the policy and lockfile fields are not implemented yet.

### Task 2: Lockfile Fields And Policy

**Files:**
- Modify: `lib/src/application/services/lockfile/shadcn_lock_repository.dart`
- Create: `lib/src/application/services/installer/namespace_collision_policy.dart`
- Modify: `lib/src/application/services/installer/installer.dart`
- Modify: `lib/src/application/services/installer/installer_manifest_part.dart`
- Modify: `lib/src/registry/component.dart`

- [ ] **Step 1: Extend lockfile model**

Add `assetPaths`, `manifestKeys`, `postInstallNamespaces`, and `localeNamespaces` fields with legacy-safe JSON parsing.

- [ ] **Step 2: Add policy**

Implement `NamespaceCollisionPolicy.checkPendingInstall()` to compare pending ownership records with existing lockfile records, skipping the same qualified component.

- [ ] **Step 3: Wire preflight**

Build the pending lockfile component before writes in `Installer.addComponent()` and call the policy before dependency/shared/file/pubspec writes.

- [ ] **Step 4: Verify green**

Run: `dart test test/installer_test.dart --reporter=expanded`

Expected: all installer tests pass.

### Task 3: Docs, Progress, And Full Verification

**Files:**
- Modify: `docs/reference/commands/components/add.md`
- Modify: `PROGRESS.md`

- [ ] **Step 1: Document convention**

Document that registry-owned manifest keys should use `<registryId>.<componentId>.<key>`.

- [ ] **Step 2: Required verification**

Run:

```bash
dart test test/installer_test.dart test/cli_integration_test.dart --concurrency=1 --reporter=expanded
dart analyze
git diff --check
graphify update .
```

Expected: all commands exit 0.
