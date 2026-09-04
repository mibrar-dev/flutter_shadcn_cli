# Final Optional Refactor Changelog Report

## Summary

This branch closes the remaining optional CLI issues tracked after the production hardening work:

- Installer refactor continuation for low-risk remaining part modules.
- Typed error contracts for resolution, path safety, registry selection, and CLI argument validation.
- Removal of service/helper process exits from the audited CLI paths.
- Final QA evidence and summary report generation.

## Before And After

### Installer Pubspec Service

**Before:** Dependency, asset, and font pubspec writes lived inside `installer_pubspec_part.dart`, increasing the installer part coupling.

**After:** `InstallerPubspecService` owns dependency preflight, dependency writes, asset writes, and font writes. The installer keeps compatibility wrappers and existing pubspec formatting preservation behavior.

### Installer Dry-Run Service

**Before:** Dry-run dependency graph traversal, plan construction, and output rendering lived in `installer_dry_run_part.dart`.

**After:** `InstallerDryRunService` owns dry-run plan generation and rendering. The installer public API remains `buildDryRunPlan` and `printDryRunPlan`.

### Installer Platform Service

**Before:** Platform target mapping, marker writes, and post-install notes lived beside generated alias code in `installer_platform_alias_part.dart`.

**After:** `InstallerPlatformService` owns platform instruction writes and post-install note reporting. Generated alias code remains separate.

### Component Resolution Errors

**Before:** `AddResolutionService` threw generic `Exception` values for malformed, missing, or ambiguous components.

**After:** `ComponentResolutionException` carries the message and offending token, and tests assert the type instead of relying only on string matching.

### Path Safety Errors

**Before:** `FilesystemGuard` used a prefix check and generic `Exception`; `/tmp/project-other` could incorrectly match `/tmp/project` by string prefix.

**After:** `FilesystemGuard` uses `path.isWithin` boundary checks and throws `PathEscapeException`. Missing project root now throws `ProjectRootNotFoundException`.

### Registry Selection Exits

**Before:** Missing registry namespaces and missing local registries could call `exit()` inside `resolveRegistrySelection`.

**After:** These paths throw `RegistryBootstrapException` with the same intended exit codes, keeping process termination at the CLI bootstrap boundary.

### Argument Parsing Exits

**Before:** Invalid `--include-files` / `--exclude-files` tokens called `exit(ExitCodes.usage)` in `parseFileKindOptions`.

**After:** `parseFileKindOptions` throws `CliArgumentException`; `runAddCommand` catches it and returns `ExitCodes.usage`.

### Version And Studio Service Exits

**Before:** `VersionManager.upgrade` and `StudioManager` service methods could call `exit()` directly.

**After:** Version upgrade throws `VersionManagerException` and `runUpgradeCommand` returns its exit code. Studio errors throw `StudioManagerException`.

## Verification

| Check | Result |
|---|---|
| `dart analyze` | PASS |
| `dart test --concurrency=1 --reporter=expanded` | PASS, `318` tests |
| Targeted refactor tests | PASS, `49` tests |
| CLI integration tests | PASS, `38` tests |

## Files Added

- `lib/src/application/services/installer/installer_pubspec_service.dart`
- `lib/src/application/services/installer/installer_dry_run_service.dart`
- `lib/src/application/services/installer/installer_platform_service.dart`
- `test/installer_pubspec_service_test.dart`
- `test/installer_dry_run_service_test.dart`
- `test/installer_platform_service_test.dart`
- `test/arg_helpers_test.dart`
- `test/filesystem_guard_test.dart`
- `test/path_utils_test.dart`
- `qa_reports/final-optional-refactor-qa-20260517211504/qa_report_summary.md`
- `qa_reports/final-optional-refactor-qa-20260517211504/changelog_report.md`

## Files Updated

- `CHANGELOG.md`
- `PROGRESS.md`
- `lib/src/application/services/add_resolution_service.dart`
- `lib/src/application/services/installer/installer.dart`
- `lib/src/application/services/installer/installer_dry_run_part.dart`
- `lib/src/application/services/installer/installer_platform_alias_part.dart`
- `lib/src/application/services/installer/installer_pubspec_part.dart`
- `lib/src/application/services/installer/installer_shared_part.dart`
- `lib/src/application/services/studio/studio_manager.dart`
- `lib/src/application/services/version/version_manager.dart`
- `lib/src/core/utils/path_utils.dart`
- `lib/src/infrastructure/resolver/filesystem_guard.dart`
- `lib/src/presentation/cli/arg_helpers.dart`
- `lib/src/presentation/cli/commands/add_command.dart`
- `lib/src/presentation/cli/commands/upgrade_command.dart`
- `lib/src/presentation/cli/registry_selection.dart`
- `test/add_resolution_service_test.dart`
- `test/registry_selection_test.dart`
