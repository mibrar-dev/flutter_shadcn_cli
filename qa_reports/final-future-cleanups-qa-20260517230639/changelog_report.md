# Future Cleanups Changelog Report

Date: 2026-05-17
Branch: `branch-v1-final-cleanups-qa-report`

## Summary

This report explains the issues found in the future cleanup pass, how they were resolved, and what the CLI does now in this variant.

## Issues And Resolutions

### 1. CLI looked idle during long installs

Before:
- Component installs showed only a high-level install line.
- Long phases such as dependency resolution, file copying, shared module installation, pubspec updates, alias generation, manifest writes, and state sync could appear stuck.
- Inline init and theme installs had similar gaps.

Resolution:
- Added `CliLogger.progress(...)` as deterministic, non-spinner progress output.
- Wired progress output into:
  - multi-registry add request resolution
  - registry preparation
  - component resolution
  - component file installation
  - shared module and shared file installation
  - bulk install finalization
  - pubspec dependency, asset, and font updates
  - alias generation
  - component manifest sync
  - state update
  - inline init action execution
  - theme preset and artifact installation

Current behavior:
- Users see stable `...` progress lines while work is happening.
- Output is deterministic and testable; no animated spinner or timing-dependent output was introduced.

### 2. Theme artifact failures used generic exceptions

Before:
- Duplicate theme targets, SHA-256 mismatch, missing source files, unsupported artifact schemes, offline remote artifact use, and failed HTTP fetches all used generic exceptions.
- Callers had to inspect message strings to understand the failure category.

Resolution:
- Added `ThemeInstallException`.
- Added stable error codes:
  - `duplicate-target`
  - `hash-mismatch`
  - `source-not-found`
  - `unsupported-source`
  - `offline-remote-source`
  - `fetch-failed`
- Kept the existing readable message text.

Current behavior:
- CLI output remains understandable.
- Programmatic callers and tests can now identify exact theme install failure categories.

### 3. Locale resource failures used generic exceptions

Before:
- Missing `l10n.yaml`, invalid `l10n.yaml`, unsupported locale formats, hash mismatches, and non-object JSON/ARB resources used generic exceptions.
- Locale install errors were harder to classify reliably.

Resolution:
- Added `LocaleInstallException`.
- Added stable error codes:
  - `missing-l10n-config`
  - `invalid-l10n-config`
  - `missing-l10n-arb-dir`
  - `missing-l10n-template-arb-file`
  - `missing-l10n-output-localization-file`
  - `unsupported-format`
  - `hash-mismatch`
  - `invalid-resource-json`
  - `invalid-json-object`

Current behavior:
- Locale-aware component installs fail with typed errors and preserved human-readable messages.
- Existing locale merge/remove behavior remains unchanged.

### 4. Pubspec dependency conflicts used generic exceptions

Before:
- Dependency conflicts during pubspec preflight/update/sync were generic exceptions.
- Tests and callers could only rely on message text.

Resolution:
- Added `PubspecUpdateException`.
- Used stable code `dependency-conflict`.
- Preserved existing conflict message text and remediation guidance.

Current behavior:
- Dependency conflicts remain user-readable and are now machine-classifiable.
- Pubspec formatting/comment preservation behavior remains unchanged.

### 5. Progress and typed error changes needed regression safety

Before:
- The cleanup work touched common install paths, so regressions could affect component install, init, themes, locale resources, and pubspec mutation.

Resolution:
- Added and updated tests for:
  - logger progress behavior
  - component install progress output
  - inline init progress output
  - typed theme artifact errors
  - typed locale install errors
  - typed pubspec conflict errors
- Ran the full CLI test suite.

Current behavior:
- `dart analyze` passes.
- Full CLI test suite passes: 327/327.
- The current branch is verified by automated regression coverage.

## Intentional Non-Changes

Direct `print(...)` calls remain in command help, JSON output, discovery rendering, feedback prompts, and studio terminal UI. Those are dedicated terminal rendering surfaces and were not changed in this pass because replacing them wholesale would be a broad UI-output refactor with higher regression risk. Install, init, theme, locale, and pubspec mutation paths were prioritized because they affect production workflows directly.

## Verification Snapshot

| Check | Result |
| --- | --- |
| `dart analyze` | Passed |
| `dart test --concurrency=1 --reporter=compact` | Passed, 327/327 |
| `git diff --check` | Passed |
| `graphify update .` | Passed |
