# Final Optional Refactor QA Report

| Field | Value |
|---|---|
| Branch | `branch-v1-final-optional-refactor-qa` |
| Base commit | `8f90105` |
| Generated | `2026-05-17T21:15:04Z` |
| Scope | Remaining optional installer refactor, exit-path hardening, typed error contracts |
| Score | `100/100` |
| Pass rate | `4/4 automated gates` |

## Result Matrix

| Gate | Command | Result | Evidence |
|---|---|---|---|
| Static analysis | `dart analyze` | PASS | `evidence/dart_analyze.txt` |
| Full repository tests | `dart test --concurrency=1 --reporter=expanded` | PASS, `318` tests | `evidence/dart_test.txt` |
| Targeted refactor regression tests | installer service, argument, registry, path, and resolution tests | PASS, `49` tests | `evidence/targeted_refactor_tests.txt` |
| CLI integration tests | `dart test test/cli_integration_test.dart --concurrency=1 --reporter=expanded` | PASS, `38` tests | `evidence/cli_integration_test.txt` |

## Issues Resolved

| Issue | Before | After |
|---|---|---|
| Remaining installer part surface | Pubspec mutation, dry-run planning, and platform instruction writes lived inside installer part extensions. | Added `InstallerPubspecService`, `InstallerDryRunService`, and `InstallerPlatformService`; part files now delegate to these services. |
| Pubspec mutation coupling | Installer owned dependency, asset, and font writes directly. | Pubspec edits are handled by `InstallerPubspecService` while preserving comments and formatting through `PubspecEditor`. |
| Dry-run logic coupling | Dry-run plan construction and rendering were embedded in an installer part. | `InstallerDryRunService` owns dependency-aware plan construction and dry-run output rendering. |
| Platform instruction coupling | Platform marker writes and post-install note reporting were embedded beside alias generation. | `InstallerPlatformService` owns platform targets, marker idempotency, and post-install note output. Alias generation remains isolated in the alias part. |
| Generic component resolution errors | `AddResolutionService` threw generic `Exception` values and tests matched message text. | Added `ComponentResolutionException` with `message` and `token`, and updated tests to assert the typed contract. |
| Path guard error typing | Filesystem root escape and missing project root errors used generic exceptions. | Added `PathEscapeException` and `ProjectRootNotFoundException`; root containment now uses canonical path boundary checks instead of prefix matching. |
| Library/service process exits | Registry selection, file-kind parsing, version upgrade, and studio service paths could call `exit()` directly. | These paths now throw typed exceptions or return command-level exit codes; `upgrade` preserves the same numeric exit behavior through `runUpgradeCommand`. |
| Explicit local registry fallback | A bad explicit `--registry-path` could fall through to auto-discovery. | Explicit bad local paths now fail with `RegistryBootstrapException` and `ExitCodes.registryNotFound`. |

## OpenCode Agent Work

Three OpenCode agents were run in read-only mode:

| Agent | Focus | Applied Result |
|---|---|---|
| Refactor audit | Remaining installer part extraction candidates | Implemented the low-risk dry-run and platform extraction recommendations; also extracted pubspec mutation with direct tests. |
| Hygiene audit | Generic exceptions, `exit()` usage, logger/print risks | Fixed production-relevant exit paths and typed core/component/path errors. Broader logger-print normalization remains cleanup, not a functional blocker. |
| QA/report audit | Final report and changelog structure | Used the proposed evidence matrix and before/after inventory for this report and `changelog_report.md`. |

## Residual Risk

No production-blocking CLI issue remains in this branch based on the verified gates. Remaining cleanup opportunities are architectural only:

- Further split high-coupling installer parts such as theme, remove, locale, and manifest logic after path resolution is extracted into a shared resolver abstraction.
- Standardize all application-layer `print()` output behind `CliLogger` or a dedicated output abstraction.
- Continue replacing generic exceptions in theme/schema/registry loaders with typed domain exceptions over future cleanup branches.

## Evidence Summary

- `dart analyze`: `No issues found!`
- Full suite: `All tests passed!` with `318` tests.
- Targeted refactor suite: `All tests passed!` with `49` tests.
- CLI integration suite: `All tests passed!` with `38` tests.
