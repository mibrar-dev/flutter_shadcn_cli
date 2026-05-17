# GAP-19 Asset Semantics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce asset-specific copy semantics so binary assets are preserved by default, pubspec assets are exact copied files, and lockfile ownership includes asset files.

**Architecture:** Keep the change inside existing registry parsing, installer file-copy/pubspec/lockfile parts, and inline init action engine. Treat asset paths as concrete operation outputs and reject merge-like strategies for binary asset extensions before writes.

**Tech Stack:** Dart CLI, package:test, local registry fixtures, existing `Installer`, `InitActionEngine`, and `ShadcnLockRepository`.

---

### Task 1: Failing Tests

**Files:**
- Modify: `test/installer_test.dart`
- Modify: `test/init_action_engine_test.dart`

- [ ] **Step 1: Write failing installer tests**

Add tests that:
- component asset files default to preserving an existing user file
- `flutter.assets` gets the exact copied asset file path, not a declared directory
- binary asset files reject merge strategies
- lockfile records asset ownership

- [ ] **Step 2: Write failing inline init tests**

Add tests that:
- preserved copied assets warn and are not added to derived `flutter.assets`
- binary inline assets reject merge strategies

- [ ] **Step 3: Run tests to verify RED**

Run: `dart test test/init_action_engine_test.dart test/installer_test.dart --reporter=expanded`

Expected: FAIL for missing GAP-19 behavior.

### Task 2: Implementation

**Files:**
- Modify: `lib/src/registry/registry_file.dart`
- Modify: `lib/src/application/services/installer/installer_file_install_part.dart`
- Modify: `lib/src/application/services/installer/installer_manifest_part.dart`
- Modify: `lib/src/application/services/installer/installer_pubspec_part.dart`
- Modify: `lib/src/application/services/init_action_engine/init_action_engine.dart`
- Modify: `lib/src/application/services/lockfile/shadcn_lock_repository.dart`

- [ ] **Step 1: Parse optional file/action strategy**

Add an optional `strategy` field to registry file parsing. Normalize supported asset strategies as `copy` and `copy_preserve_user`.

- [ ] **Step 2: Enforce binary asset strategy**

Reject merge-like strategies for `.png`, `.jpg`, `.jpeg`, `.webp`, `.ttf`, `.otf`, `.woff`, `.woff2`, and `.svg`.

- [ ] **Step 3: Preserve user-visible assets**

Default binary/user-visible assets to preserve existing files. Log a warning when a preserve policy skips an existing destination.

- [ ] **Step 4: Use exact copied asset paths**

Track installed component file destinations during the operation and update `flutter.assets` only with exact copied asset file paths matching component asset declarations.

- [ ] **Step 5: Record lockfile asset ownership**

Add a minimal compatible `assetFiles` list to lockfile component records and keep existing JSON load behavior backward compatible.

### Task 3: Verification

**Files:**
- Modify: `PROGRESS.md`

- [ ] **Step 1: Run focused tests**

Run: `dart test test/init_action_engine_test.dart test/installer_test.dart --reporter=expanded`

- [ ] **Step 2: Run analyzer and whitespace checks**

Run: `dart analyze`

Run: `git diff --check`

- [ ] **Step 3: Update graphify**

Run: `graphify update .`

- [ ] **Step 4: Commit and push**

Run: `git status --short`

Run: `git add ...`

Run: `git commit -m "fix: enforce asset copy semantics"`

Run: `git push origin branch-v1-gap-19-asset-semantics`
