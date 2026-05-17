# Interactive CLI QA Report

Date: 2026-05-17
Branch: `branch-v1-interactive-cli-qa`
Fresh Flutter app: `/tmp/flutter_shadcn_interactive_qa.sTBPgm/app`
Real registry root: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/lib/registry`

## Summary

QA score: 100/100 after the registry metadata fix.

This QA run tested the CLI like a normal user would: `init` was run interactively without `--yes`. The test then installed components, checked generated files, validated the registry, audited installed files, ran dependency checks, and verified the generated Flutter app with `flutter pub get` and `flutter analyze`.

## Interactive Init Behavior

Command:

```bash
dart bin/shadcn.dart --advanced init --registry-path /tmp/flutter_shadcn_interactive_qa.sTBPgm/source_overlay/registry
```

Inputs provided:

- Component install path: Enter, keeping `lib/ui/shadcn`
- Shared files path: Enter, keeping `lib/ui/shadcn/shared`
- Optional font/icon asset groups: Enter, skipping all optional assets
- Theme selection: `999`, then Enter after the CLI rejected the invalid value

Observed behavior:

- The CLI asked for component install path.
- The CLI asked for shared files path.
- The CLI asked whether to install optional font/icon asset groups.
- The CLI listed 42 starter themes.
- Invalid theme input `999` produced an error and re-prompted.
- Pressing Enter skipped theme selection.
- Init copied 48 core shared files and created 3 directories.
- No `assets/` files were created when optional font/icon groups were skipped.

Important init outputs:

- `Install font assets?`
- `Select numbers separated by comma, "a" for all, or Enter to skip:`
- `Theme number or id (Enter to skip): 999`
- `Invalid theme selection "999". Choose 1-42 or press Enter to skip.`
- `Skipping theme selection.`

## Component Install Checks

Selected component install commands:

```bash
dart bin/shadcn.dart --advanced add button --registry-path <registry>
dart bin/shadcn.dart --advanced add card --registry-path <registry>
dart bin/shadcn.dart --advanced add alert --registry-path <registry>
```

Selected install result:

- Component manifests created: `button.json`, `card.json`, `alert.json`
- `shadcn.lock` installed file records checked: 77
- Missing installed files: 0
- Total project files after selected install: 213

All-component install command:

```bash
dart bin/shadcn.dart --advanced add <all 133 component ids> --registry-path <registry>
```

All-component install result:

- Components installed: 133
- `shadcn.lock` installed file records checked: 1,497
- Missing installed files: 0
- Total project files after all install: 1,921

## Issue Found And Fixed

| ID | Before | Fix | After |
| --- | --- | --- | --- |
| INT-QA-01 | `validate --json` reported missing required file dependency `registry/components/display/markdown/_impl/state/markdown_live_preview.dart`. The source file existed, but registry manifests did not list it as a markdown component file. | Added `markdown_live_preview.dart` to both `/flutter_shadcn_kit/lib/registry/components/display/markdown/meta.json` and `/flutter_shadcn_kit/lib/registry/manifests/components.json`. | `validate --json` passes with 1,834 source files checked and no missing dependencies. Full all-component install includes `markdown_live_preview.dart`. |

## Verification Evidence

| Gate | Result |
| --- | --- |
| Interactive init without `--yes` | PASS |
| Optional font/icon asset skip | PASS, no `assets/` files after init |
| Invalid theme input re-prompt | PASS |
| Selected install file existence | PASS, 77 checked, 0 missing |
| All component install file existence | PASS, 1,497 checked, 0 missing |
| `deps --all --json` | PASS |
| `validate --json` | PASS, 1,834 source files checked |
| `audit --json` | PASS, 133 installed, no missing files |
| `flutter pub get` | PASS |
| `flutter analyze` | PASS, no issues found |

## Evidence Logs

Log root:

```text
/tmp/flutter_shadcn_interactive_qa.sTBPgm/logs
```

Key files:

- `interactive_init.log`
- `files_after_init.txt`
- `assets_after_init.txt`
- `installed_file_check_selected.json`
- `installed_file_check_all.json`
- `validate_after_markdown_fix_json.log`
- `validate_after_all_json.log`
- `audit_after_all_json.log`
- `deps_after_all_json.log`
- `flutter_pub_get_after_all.log`
- `flutter_analyze_after_all.log`

## Current State

The interactive CLI path is working for the tested production flow. Init does not silently install optional assets when the user skips them, invalid theme choices re-prompt, selected and full component installs produce complete file sets, and the generated Flutter app analyzes cleanly after all components are installed.
