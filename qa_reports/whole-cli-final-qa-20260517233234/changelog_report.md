# Whole CLI Final Changelog Report

Date: 2026-05-17
Branch: `branch-v1-whole-cli-final-qa`

## 1. Real kit registry add failed after init

Problem:
`tool/cli_manual_smoke.sh` failed in a fresh Flutter project when running `add button` against `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/lib/registry`.

Before:
The CLI checked `registry/components/control/button/button.meta.json` before `registry/components/control/button/meta.json`. In the kit registry, `button.meta.json` is documentation/readme metadata and does not contain install `files`. Parsing it as a component install manifest caused a malformed manifest exception.

Resolution:
`ComponentManifestResolver` now:

- prefers `meta.json` as component install metadata
- checks `{id}.meta.json` after `meta.json`
- skips docs-only metadata that declares `readme_meta.schema.json`
- normalizes kit-style install metadata into the internal component model
- expands relative file paths into install source/destination pairs
- maps grouped dependency data into `shared`, `dependsOn`, and `pubspec.dependencies`

Current behavior:
The same fresh-app smoke run now passes init and component add/file checks.

## 2. Regression coverage added

Problem:
The existing resolver tests only covered component-local manifests that already matched the internal component JSON shape.

Resolution:
Added `ComponentManifestResolver normalizes kit-style component meta and skips docs meta`.

Current behavior:
The focused resolver suite passes 4/4 and the full CLI suite passes 328/328.

## 3. QA evidence refreshed

Commands run:

- `dart analyze`
- `dart test test/component_manifest_resolver_test.dart --reporter=expanded`
- `bash tool/cli_manual_smoke.sh --registry-root /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/lib/registry`
- `dart test --concurrency=1 --reporter=compact`
- `git diff --check`
- `graphify update .`

Result:
All gates passed. Final score: 100/100.
