# Changelog

## Unreleased

## 0.2.1

### Release Readiness
- Bumped the CLI package version for the minimal fixture release.
- Verified installer and init copy flows expose visible progress/loading feedback through `CliLogger.progress`.
- Added release QA artifacts for the default app init and registry bootstrap changes.

### Registry Bootstrap
- Aligned the default interactive init path with the lean app bootstrap policy.
- Kept scaffold, divider, localization extension helpers, and font/icon assets out of default init unless explicitly selected or installed.

### Internal Refactors
- Extracted installer pubspec mutation, dry-run planning, and platform instruction writes into dedicated services.
- Added direct service tests for pubspec preservation, dry-run dependency projection, and platform marker idempotency.

### Safety & Errors
- Replaced service/helper `exit()` paths in registry selection, file-kind parsing, version upgrade, and studio management with typed exceptions or command-level exit-code returns.
- Added typed exceptions for component resolution failures, filesystem root escapes, and missing Flutter project roots.
- Tightened explicit `--registry-path` handling so a bad explicit local path fails instead of falling back to auto-discovery.

### QA
- Added final optional-refactor QA and changelog reporting artifacts under `qa_reports/`.

## 0.2.0

### 🧭 Multi-Registry v1
- **NEW**: Multi-registry namespace architecture with per-registry config/state addressing.
- **NEW**: Registry directory (`registries.json`) loading with schema validation and local cache support.
- **NEW**: Namespace bootstrap via `flutter_shadcn init <namespace>` executing inline init actions.
- **NEW**: Namespace-qualified component references:
  - Preferred: `@namespace/component`
  - Backward-compatible: `namespace:component`
- **NEW**: `registries` command to list configured/discovered registries.
- **NEW**: `default` command to get/set default registry namespace.

### 🧩 Compatibility
- **IMPROVED**: Automatic migration of legacy `.shadcn/config.json` to `registries` map format.
- **IMPROVED**: Automatic migration of legacy `.shadcn/state.json` to `registries` state format.
- **IMPROVED**: Existing single-registry behavior preserved while routing through new engine.

### 🔒 Safety
- **IMPROVED**: URL resolver validation and base URL normalization for registry fetches.
- **IMPROVED**: Strict filesystem traversal protection on all write targets.

## 0.1.9

### 🧾 Output & Automation
- **NEW**: Pretty-printed `--json` output for list, search, info, doctor, dry-run, validate, audit, and deps.
- **NEW**: Standardized JSON envelope with `status`, `data`, `errors`, `warnings`, `meta`.
- **NEW**: Standardized exit codes for common failure categories.

### 🧭 CLI Ergonomics
- **NEW**: Command aliases `ls` → `list`, `rm` → `remove`, `i` → `info`.
- **NEW**: `--offline` mode for cache-only registry/index usage.
- **IMPROVED**: Init flow now shows a summary and confirms before writing (unless `--yes`).

### 📚 Documentation
- **IMPROVED**: Updated README and site docs for new commands, JSON output, offline mode, and exit codes.

### ✅ Registry Integrity
- **NEW**: `validate` command for schema + registry integrity checks.
- **NEW**: `audit` command to compare installed components vs registry metadata.
- **NEW**: `deps` command to compare registry deps vs pubspec.yaml.

### ⚡ Performance
- **IMPROVED**: Parallelized per-component file installs with bounded concurrency.

## 0.1.8

### 🧭 Registry & Schema
- **IMPROVED**: components.json schema validation now uses JSON Schema with `$schema` resolution and local fallback to `components.schema.json`.

### 📦 Install Manifests
- **NEW**: Per-component install manifests at `.shadcn/components/<id>.json` (version/tags + audit data).
- **IMPROVED**: `<installPath>/components.json` now stores component metadata (version/tags).

### 🧰 Init & Install
- **CHANGED**: `init --add` removed; pass components positionally (e.g., `flutter_shadcn init button dialog`).
- **IMPROVED**: Shared dependency closure for init/shared installs, plus cross-registry file dependency resolution.

### 🧪 Tests
- **NEW**: Integration tests validating CLI install behavior and schema validation.

### 🎯 Component Discovery
- **NEW**: Component discovery system with `list`, `search`, and `info` commands.
  - Browse components by category with `list`
  - Search with relevance scoring via `search <query>`
  - View detailed component info with `info <component-id>`
- **NEW**: Intelligent index.json caching (24-hour staleness policy).
  - Cache location: `~/.flutter_shadcn/cache/{registryId}/index.json`
  - Local index.json support with remote fallback
  - Use `--refresh` flag to force cache update from remote

### 🔧 Project Management Commands
- **NEW**: Dry-run command to preview component installs (deps, shared, assets, fonts, platform changes).
- **NEW**: Doctor validates components.json against components.schema.json and reports cache paths.

### 📦 Version Management
- **NEW**: `version` command to show current CLI version and check for updates.
  - Use `flutter_shadcn version` to display current version
  - Use `flutter_shadcn version --check` to check for available updates
- **NEW**: `upgrade` command to upgrade CLI to the latest version.
  - Automatically fetches and installs the latest version from pub.dev
  - Use `--force` flag to force upgrade even if already on latest
- **NEW**: Automatic update checking on every CLI command.
  - Checks pub.dev once per 24 hours (rate-limited)
  - Shows subtle notification if newer version available
  - Cached in `~/.flutter_shadcn/cache/version_check.json`
  - Opt-out via `.shadcn/config.json`: set `"checkUpdates": false`

### 💬 User Feedback
- **NEW**: `feedback` command for submitting feedback and reporting issues.
  - Interactive menu with 6 feedback categories (bug, feature, docs, question, performance, other)
  - Opens GitHub with pre-filled issue templates
  - Auto-includes CLI version, OS, and Dart version for better context
  - Each feedback type has custom emoji, labels, and structured template
  - Cross-platform browser opening (macOS, Linux, Windows)

### 🧪 Testing & Quality
- **NEW**: Comprehensive test coverage for version management, registry validation, install workflows, and command behavior.

### 🐛 Bug Fixes
- **FIX**: Graceful error handling for component discovery failures.

## 0.1.7

- **BREAKING**: Complete theme preset overhaul with 42 new modern themes.
- New theme presets: amber-minimal, amethyst-haze, bold-tech, bubblegum, caffeine, candyland, catppuccin, claude, claymorphism, clean-slate, cosmic-night, cyberpunk, darkmatter, doom-64, elegant-luxury, graphite, kodama-grove, midnight-bloom, mocha-mousse, modern-minimal, mono, nature, neo-brutalism, northern-lights, notebook, ocean-breeze, pastel-dreams, perpetuity, quantum-rose, retro-arcade, sage-garden, soft-pop, solar-dusk, starry-night, sunset-horizon, supabase, t3-chat, tangerine, twitter, vercel, vintage-paper, violet-bloom.
- Fix repository URL in pubspec.yaml for pub.dev validation.
- Follow Dart file conventions for better code organization.
- Remove all previous theme presets in favor of new collection.

## 0.1.6

- Add Dartdoc for public APIs and export preset theme data.
- Add CLI example script for pub.dev package validation.
- Update dependency constraints to latest compatible versions.
- Refresh pubspec description and project links.

## 0.1.5

- Add file-level dependsOn support for component/shared files.
- Apply platform-specific instructions with configurable targets.
- Add platform command to set/reset target overrides.
- Report post-install notes for components.
- Prettify CLI output with colors and sections.

## 0.1.4

- Experimental theme install from JSON file/URL (gated by --experimental).
- WIP/experimental feature flags added to CLI.
- Batched dependency updates using dart pub add/remove.
- remove --all now cleans empty parent folders.
- Theme preset application bugfix (color hex replacement).
- Clearer init prompts and expanded help output.
- Added documentation, PRD, and example theme JSON.

## 0.1.3

- Add `sync` command to apply .shadcn/config.json changes (paths + theme).
- Track installed components in project components.json.
- Add `remove --all` and bulk removal support.
- Ensure init files are created before add/remove.

## 0.1.2

- Add dev registry mode and init one-shot flags.
- Improve README for end users and pub.dev.
- Add tests and integration coverage.
- Normalize install/shared paths and alias handling.
- Install core shared helpers + deps during init.
