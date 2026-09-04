# Whole CLI Final QA Report

Date: 2026-05-17
Branch: `branch-v1-whole-cli-final-qa`
Scope: final whole-CLI pass covering the remaining future-cleanup work, manifest-first installs, loading feedback, typed install errors, real-registry smoke behavior, and regression evidence.

## Executive Summary

QA score: 100/100
Automated pass rate: 328/328 tests passed
Fresh real-registry smoke: passed
Static analysis: clean

This pass found and fixed one remaining production issue during a disposable Flutter app smoke run against the real kit registry. `flutter_shadcn add button` failed because the CLI treated `button.meta.json` documentation metadata as the component install manifest before reading the real install `meta.json`. The resolver now prefers install `meta.json`, skips docs-only `*.meta.json` files that use `readme_meta.schema.json`, and normalizes the kit registry's relative file list plus grouped dependency metadata into the CLI's internal component model.

## Issue Found In This Pass

| ID | Before | Root cause | Resolution | Now |
| --- | --- | --- | --- | --- |
| FINAL-01 | Fresh-app smoke failed on `add button` with `type 'Null' is not a subtype of type 'List<dynamic>'` | `button.meta.json` is docs metadata, while `meta.json` is install metadata. The resolver tried the docs file first and parsed it as a component manifest. | `ComponentManifestResolver` now tries `meta.json` before `{id}.meta.json`, skips docs-only metadata, and normalizes kit-style manifest fields. | Fresh smoke passes `init`, `add button`, `add card`, `add alert`, and expected file checks. |

## What Changed

| Area | Before | Now |
| --- | --- | --- |
| Component-local source of truth | Required component-local manifest files to already match the internal `Component.fromJson` shape. | Accepts the real kit registry install metadata shape from `meta.json` and maps it to internal install data. |
| Docs metadata handling | `{component}.meta.json` could be mistaken for install metadata. | Docs metadata with `readme_meta.schema.json` or docs-only fields is skipped for install resolution. |
| File entries | Relative strings in per-component `meta.json` were not accepted by the resolver. | Relative file strings are expanded to `registry/components/<category>/<id>/...` and `{installPath}/components/<category>/<id>/...`. |
| Dependency entries | Kit metadata grouped dependencies under `dependencies.shared`, `dependencies.components`, and `dependencies.pubspec`. | These are normalized to `shared`, `dependsOn`, and `pubspec.dependencies`. |
| Regression coverage | Existing tests covered strict internal manifest shape only. | Added regression coverage for kit-style metadata plus docs metadata skip behavior. |

## Verification Evidence

| Gate | Command | Result |
| --- | --- | --- |
| Static analysis | `dart analyze` | PASS, no issues found |
| Focused regression | `dart test test/component_manifest_resolver_test.dart --reporter=expanded` | PASS, 4/4 |
| Full test suite | `dart test --concurrency=1 --reporter=compact` | PASS, 328/328 |
| Whitespace diff | `git diff --check` | PASS |
| Code graph refresh | `graphify update .` | PASS, 1471 nodes and 1919 edges |
| Real kit smoke | `bash tool/cli_manual_smoke.sh --registry-root /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/lib/registry` | PASS |

Smoke evidence:

- Initial failing command: `dart bin/shadcn.dart --advanced add button --registry-path <overlay>/registry`
- Failure before fix: malformed component manifest from `registry/components/control/button/button.meta.json`
- Passing rerun: `Smoke passed init/add/file checks.`
- Smoke log directory: `/tmp/flutter_shadcn_manual_smoke.0r7ydj/logs`

## Command And Feature Coverage

| Feature family | Evidence |
| --- | --- |
| Init engine | Integration tests and real smoke verify `init --yes`, inline init actions, progress output, pubspec merge, and path restrictions. |
| Add/install | Full suite and real smoke verify component add, shared dependency installation, manifest-first resolution, file writes, pubspec updates, and state updates. |
| Registry source of truth | Component manifest resolver tests verify local manifest preference, fallback to `components.json`, malformed install manifest errors, and kit-style manifest normalization. |
| Locale | Full suite verifies per-component locale merge behavior, typed locale install failures, `l10n.yaml` handling, and locale resource ownership. |
| Theme | Full suite verifies theme preset loading, progress output, typed theme artifact failures, and theme artifact application. |
| Pubspec | Full suite verifies comment-preserving dependency/assets/fonts edits, conflict detection, rollback, and structured SDK dependency handling. |
| Safety | Full suite verifies path traversal rejection, symlink escape rejection, lib/assets init boundaries, install target boundaries, and namespace collision checks. |
| CLI output | OpenCode read-only audit found zero production mutation risks from remaining direct terminal output calls. Remaining `print`/`stdout` usage is help text, prompts, dry-run rendering, discovery output, studio/status output, and interactive selections. |

## Current State

The CLI is production-ready for the tested scope in this branch:

- Analysis is clean.
- Full automated suite passes at 328/328.
- Real-registry disposable Flutter smoke passes.
- Manifest-first install resolution works with the real kit registry's per-component metadata format.
- Existing loading feedback and typed install error contracts remain intact.
- No production mutation risk was found in remaining direct terminal output usage.

## Residual Risk

No blocking issues remain from this pass. Cross-platform CI and hosted pub.dev scoring are outside this local QA run, but the Dart analysis/test/smoke evidence is clean on this machine.
