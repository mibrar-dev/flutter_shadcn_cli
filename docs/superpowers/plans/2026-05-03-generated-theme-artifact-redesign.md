# Generated Theme Artifact Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove runtime registry theme converter execution and replace it with a generated, hash-verified theme artifact contract consumed safely by the CLI.

**Architecture:** `registry-directory` publishes only declarative theme metadata, `shadcn_flutter_kit` generates theme artifacts and manifest files at publish time, and `shadcn_flutter_cli` installs only verified artifacts. Advanced `theme --apply-file` and `theme --apply-url` remain, but only as experimental manifest-driven inputs; no user-machine code execution remains.

**Tech Stack:** Dart CLI, JSON schema validation, SHA-256 hashing, Flutter/Dart file generation, existing multi-registry installer and path-guard utilities.

---

## File map

### registry-directory
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/registry-directory/registries/registries.schema.json`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/registry-directory/registries/entries/official.json`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/registry-directory/registries/registries.json`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/registry-directory/README.md`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/registry-directory/CONTRIBUTING.md`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/registry-directory/registries/README.md`

### shadcn_flutter_kit
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/tool/theme/theme_index_generate.dart`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/tool/theme/README.md`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/tool/theme/theme_index_generate_readme.md`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/tool/theme/theme_preset_json_to_dart.dart`
- Modify or create generated theme manifest and output files under `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/lib/registry/manifests/` and `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/lib/registry/shared/theme/`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/docs/lib/pages/docs/cli_reference_data.dart`

### shadcn_flutter_cli
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/lib/src/infrastructure/registry_directory/registry_directory_entry.dart`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/lib/src/config/registry_config_entry.dart`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/lib/src/schemas/registries.schema.json`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/lib/src/presentation/cli/commands/theme_command.dart`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/lib/src/application/services/installer/installer_theme_part.dart`
- Delete or replace: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/lib/src/infrastructure/registry/registry_theme_converter_client.dart`
- Modify or replace: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/lib/src/infrastructure/registry/theme_preset_loader.dart`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/lib/src/application/services/multi_registry/multi_registry_init_part.dart`
- Modify docs under `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/docs/`
- Modify tests:
  - `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/test/theme_loader_test.dart`
  - `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/test/widget_theme_installer_test.dart`
  - `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/test/installer_test.dart`
  - `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/test/cli_integration_test.dart`
  - `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/test/registry_directory_test.dart`
  - Add focused artifact install tests if needed

---

### Task 1: Registry schema and official metadata

**Files:**
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/registry-directory/registries/registries.schema.json`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/registry-directory/registries/entries/official.json`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/registry-directory/registries/registries.json`

- [ ] **Step 1: Write the failing schema test/check**

Use schema validation on a copied official entry that still contains `themeConverterDart` and expect failure after schema change.

Run: `node -e "const Ajv=require('ajv/dist/2020'); const fs=require('fs'); const schema=JSON.parse(fs.readFileSync('registries/registries.schema.json','utf8')); const data=JSON.parse(fs.readFileSync('registries/registries.json','utf8')); const ajv=new Ajv({allErrors:true,strict:false}); const validate=ajv.compile(schema); console.log(validate(data), validate.errors);"`

Expected after schema edit and before metadata update: `false` with error pointing at `themeConverterDart` or missing new theme file contract.

- [ ] **Step 2: Remove runtime converter field from schema and add declarative theme file contract**

Add schema defs for:
- theme index objects
- theme file artifacts
- SHA-256 pattern
- safe source path or HTTPS URL
- safe relative target path

Remove `paths.themeConverterDart` entirely.

- [ ] **Step 3: Update official registry entry to publish only generated artifact metadata**

Replace `paths.themeConverterDart` with only:
- `themesJson`
- `themesSchemaJson`

Point `themesJson` to the generated theme artifact manifest path that kit tooling will produce.

- [ ] **Step 4: Regenerate `registries.json` and rerun validation**

Run the repo’s registry build command and schema validation.

Expected: validation passes with no converter field present.

- [ ] **Step 5: Commit**

`git commit -m "feat(schema): publish declarative theme artifact contract"`

### Task 2: Publish-time theme artifact generation in shadcn_flutter_kit

**Files:**
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/tool/theme/theme_index_generate.dart`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/tool/theme/theme_preset_json_to_dart.dart`
- Modify generated manifests and generated theme files under `flutter_shadcn_kit/lib/registry/`

- [ ] **Step 1: Write a failing generation test or dry-run check**

Run the generator and inspect the output shape.

Run: `dart run flutter_shadcn_kit/tool/theme/theme_index_generate.dart --output manifests/theme.index.json`

Expected before implementation: output still contains old `id/name/file/preview` shape and no `files[].sha256`.

- [ ] **Step 2: Refactor generator output to manifest-driven artifacts**

For each theme preset, emit:
- `name`
- `label`
- `description`
- `source`
- `files[]`

Generate the Dart artifact files first, then hash them, then write the manifest.

- [ ] **Step 3: Separate generator mode from legacy converter envelope handling**

`theme_preset_json_to_dart.dart` must stop serving as a CLI runtime converter.
It may remain as a local generation tool, but remove stdin/request-envelope execution semantics used by the CLI.

- [ ] **Step 4: Regenerate checked-in artifacts and manifest**

Run the generator and verify the official manifest and generated files are deterministic.

- [ ] **Step 5: Commit**

`git commit -m "refactor(tooling): generate hashed theme artifacts"`

### Task 3: CLI theme installation without code execution

**Files:**
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/lib/src/application/services/installer/installer_theme_part.dart`
- Delete or replace: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/lib/src/infrastructure/registry/registry_theme_converter_client.dart`
- Modify or replace: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/lib/src/infrastructure/registry/theme_preset_loader.dart`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/lib/src/application/services/multi_registry/multi_registry_init_part.dart`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/lib/src/infrastructure/registry_directory/registry_directory_entry.dart`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/lib/src/config/registry_config_entry.dart`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/lib/src/schemas/registries.schema.json`

- [ ] **Step 1: Write failing tests for artifact-based theme install**

Add tests covering:
- one-file theme install
- multi-file theme install
- hash mismatch aborts before writes
- dangerous target aborts before writes
- init theme apply path uses artifact install

Run: `dart test test/installer_test.dart test/theme_loader_test.dart -r expanded`

Expected before implementation: failures because current code expects converter behavior.

- [ ] **Step 2: Implement typed theme artifact models and loader**

Replace converter-dependent preset loading with theme index parsing that returns a selected theme and its file list.

- [ ] **Step 3: Implement download/verify/validate/write pipeline**

The pipeline must:
- resolve all sources
- download/cache all files
- verify SHA-256
- validate targets with existing path guard
- write only after the entire set passes
- record installed theme files

- [ ] **Step 4: Remove runtime converter execution paths**

Delete or dead-code-remove:
- converter client execution
- request envelope handling assumptions
- config wiring for `themeConverterDartPath`
- init path that calls `applyThemeFromJson()`

- [ ] **Step 5: Commit**

`git commit -m "refactor(cli): install generated theme artifacts safely"`

### Task 4: Keep advanced file/url theme inputs as experimental manifest inputs

**Files:**
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/lib/src/presentation/cli/commands/theme_command.dart`
- Modify relevant loader/install files in CLI
- Modify docs under `docs/developer/advanced-mode.md` and command refs

- [ ] **Step 1: Write failing CLI/integration tests**

Cover:
- `theme --apply-file` behind `--advanced`
- `theme --apply-url` behind `--advanced`
- both paths accept only declarative manifest payloads
- non-advanced use still errors

- [ ] **Step 2: Re-scope advanced commands**

Make `--apply-file` and `--apply-url` load a declarative artifact manifest only.
Do not accept raw preset JSON or any payload that requires code execution.

- [ ] **Step 3: Remove widget converter-owned theme flows or gate them off**

If widget theme cannot be expressed with the same manifest contract yet, hide it behind advanced experimental messaging and make unsupported actions fail explicitly rather than executing code.

- [ ] **Step 4: Commit**

`git commit -m "refactor(cli): gate experimental manifest theme inputs"`

### Task 5: Docs, website sync, and cleanup

**Files:**
- Modify CLI docs under `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/docs/`
- Modify website docs data: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/docs/lib/pages/docs/cli_reference_data.dart`
- Modify registry docs in `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/registry-directory/`

- [ ] **Step 1: Remove converter language everywhere**

Search terms:
`themeConverter`
`themeConverterDart`
`runtime converter`
`apply theme JSON`
`widget theme converter`

- [ ] **Step 2: Update docs to describe the new contract**

Use this wording:
`Each registry owns its theme format and generation pipeline. Conversion should happen at registry publish time. The CLI consumes only pre-generated, hash-verified theme artifacts.`

- [ ] **Step 3: Sync website reference text with CLI docs**

Update the docs site data so it matches the new command semantics and advanced experimental gating.

- [ ] **Step 4: Run verification**

CLI:
- `dart analyze`
- `dart test`
- `graphify update .`

Registry directory:
- repo schema/build validation

Kit:
- run theme generator commands used by the official registry

- [ ] **Step 5: Commit docs and cleanup**

`git commit -m "docs: document generated theme artifact workflow"`

---

## Self-review

- Spec coverage: runtime converter removal, schema update, official registry update, publish-time generation, safe CLI install, advanced experimental file/url handling, docs, and tests are all mapped to tasks.
- Placeholder scan: no TODO/TBD placeholders remain.
- Type consistency: `theme file artifact`, `themesJson`, and advanced manifest inputs use the same declarative model across all tasks.
