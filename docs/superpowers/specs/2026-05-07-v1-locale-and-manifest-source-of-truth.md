# V1 Locale And Component Manifest Source-Of-Truth Spec

## Problem

The current v1 multi-registry design treats `components.json` as the primary install manifest. That blocks registries from publishing smaller per-component manifests, makes component install metadata harder to cache independently, and leaves locale resources outside the v1 contract.

Locale support is in v1. Per-component manifests are the source of truth for install when present. `components.json` and `index.json` are fallbacks only.

No required `meta.json` fetch for bootstrap remains true. `flutter_shadcn init <namespace>` continues to execute inline `init.actions` from `registries.json` directly.

## How To Solve

Define a v1 component resolution contract with this install metadata precedence:

1. Per-component manifest.
2. `components.json`.
3. `index.json` summary only when the selected index entry contains enough install metadata to perform the install exactly.

If `index.json` lacks required install metadata, the command fails with a clear error. The CLI must not guess source files, destination paths, dependencies, shared groups, assets, post-install instructions, platform files, locale resources, or hashes.

The CLI caches registry manifest capability per registry namespace and source hash. When a registry has no per-component manifests, later commands skip manifest probes for that same registry until the registry identity changes or the user forces refresh.

## Normative Decisions

- Locale support is part of v1.
- A per-component manifest is the source of truth for install when present.
- Fallback order is per-component manifest, then `components.json`, then `index.json` summary only when the index entry contains enough install metadata.
- `index.json` without complete install metadata is not an install source.
- Registry capability cache records manifest support per registry namespace and source hash.
- If no per-component manifests are found for a registry, the CLI skips manifest probes on later commands until source hash, ETag, `baseUrl`, or `componentsPath` changes, or until the user forces refresh.
- Bootstrap does not require `meta.json`.
- Single-registry projects keep working and legacy `.shadcn/config.json` / `.shadcn/state.json` migration remains required.
- `.shadcn/state.json.managedDependencies` behavior remains intact.

## Per-Component Manifest

### Location

The registry directory may declare:

```json
{
  "paths": {
    "componentsJson": "components.json",
    "componentManifests": "components/{id}.json",
    "indexJson": "index.json"
  }
}
```

`paths.componentManifests` is a registry-relative template. It must contain exactly one `{id}` token. The CLI replaces `{id}` with the normalized component id after validating that the id matches `^[a-z0-9][a-z0-9_-]{0,63}$`.

When `paths.componentManifests` is absent, the default probe path is `components/{id}.json`.

All manifest paths use the existing v1 resolver rules: no leading slash, no `..`, no backslash, no `?`, no `#`, no empty segments, and no absolute URLs inside registry-relative path fields.

### Shape

Per-component manifest JSON must be an object:

```json
{
  "schemaVersion": 1,
  "id": "button",
  "name": "Button",
  "category": "forms",
  "version": "1.2.0",
  "description": "Clickable button primitives.",
  "tags": ["form", "action"],
  "files": [
    {
      "source": "registry/components/button/button.dart",
      "destination": "button.dart",
      "kind": "component",
      "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "dependsOn": [
        {
          "source": "registry/components/button/button_style.dart",
          "destination": "button_style.dart"
        }
      ]
    }
  ],
  "shared": ["theme", "tokens"],
  "dependsOn": ["icon"],
  "pubspec": {
    "dependencies": {
      "collection": "^1.18.0"
    },
    "devDependencies": {},
    "flutterAssets": ["assets/shadcn/button/"],
    "flutterFonts": []
  },
  "assets": [
    {
      "source": "registry/assets/button/check.svg",
      "destination": "assets/shadcn/button/check.svg",
      "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    }
  ],
  "postInstall": [
    "Run dart format after installation."
  ],
  "platform": {
    "ios": {
      "files": [
        {
          "source": "registry/platform/ios/button.dart",
          "destination": "ios/button.dart",
          "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        }
      ]
    }
  },
  "locale": {
    "defaultLocale": "en",
    "required": ["en"],
    "optional": ["es", "fr"],
    "resources": [
      {
        "locale": "en",
        "format": "arb",
        "source": "registry/l10n/button_en.arb",
        "destinationName": "button_en.arb",
        "required": true,
        "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
      },
      {
        "locale": "es",
        "format": "json",
        "source": "registry/l10n/button_es.json",
        "destinationName": "button_es.json",
        "required": false,
        "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
      }
    ]
  },
  "hashes": {
    "manifestSha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "contentSha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  }
}
```

Required fields: `schemaVersion`, `id`, `name`, and `files`. `files` may be empty only for marker components that have at least one non-empty install section among `shared`, `dependsOn`, `pubspec`, `assets`, `platform`, or `locale.resources`.

The CLI must reject a manifest when its `id` does not equal the requested component id. A qualified request such as `@shadcn/button` must resolve a manifest whose id is exactly `button`.

### Install Metadata Completeness

An install source is complete when it can answer all installer decisions without another install-source fetch:

- component identity: `id`, `name`, `version`, `category`, `tags`
- files: `source`, `destination`, optional `kind`, optional file `dependsOn`, optional `sha256`
- shared groups: `shared`
- component dependencies: `dependsOn`
- package changes: `pubspec.dependencies`, `pubspec.devDependencies`, `pubspec.flutterAssets`, `pubspec.flutterFonts`
- assets: `source`, `destination`, optional `sha256`
- post-install messages: `postInstall`
- platform-specific install metadata: `platform`
- locale resources: `locale`
- hashes: manifest/content hashes when published

`components.json` is complete when its component object has the same fields. `index.json` is complete only when its matching entry has the same fields needed for install. Search-only fields such as `id`, `name`, `description`, `tags`, and `category` are not enough.

## Locale V1 Contract

### Supported Formats

V1 supports ARB and JSON locale resources.

`format: "arb"` resources must parse as JSON objects. ARB metadata keys beginning with `@` are preserved exactly. For every non-metadata message key that has a matching `@messageKey` metadata object, the CLI copies both entries together. The CLI must reject malformed ARB JSON and must not rewrite placeholders, descriptions, examples, or custom ARB metadata.

`format: "json"` resources must parse as JSON objects. The CLI copies them as data files and does not infer Flutter localization semantics from arbitrary JSON.

### Consumer Project Configuration

The CLI reads `l10n.yaml` from the project root. If `l10n.yaml` is absent, locale installation fails with this actionable error:

`Locale resources require l10n.yaml. Run flutter_shadcn locale init, or create l10n.yaml with arb-dir, template-arb-file, and output-localization-file before installing locale-aware components.`

V1 adds `flutter_shadcn locale init`. The command creates `l10n.yaml` only when it does not already exist:

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```

It also ensures `lib/l10n/` exists. It does not add generated localization delegates to application code because there is no safe project-wide insertion point in v1.

When `l10n.yaml` exists, the CLI uses `arb-dir` as the locale destination directory. If `arb-dir` is absent or empty, locale install fails with a clear error. If `template-arb-file` or `output-localization-file` is absent, `doctor` reports it and install fails for ARB resources.

### Locale Selection

Locale selection is deterministic:

1. Project supported locales from existing files in `arb-dir`, `l10n.yaml` metadata when available, and Flutter `supportedLocales` only when it can be read from generated localization metadata.
2. Config override from `.shadcn/config.json` under `locale.supportedLocales`.
3. Registry default locale from the component manifest `locale.defaultLocale`.

There is no silent all-locale install. If no selected locales can be derived, the CLI installs only the registry default locale. If the registry default locale is absent, install fails and asks the user to configure `.shadcn/config.json.locale.supportedLocales`.

`--locale <locale>` may narrow the selection for commands that install or update components. The flag must be explicit and repeatable. It must not select locales not published by the component unless the command is only planning a dry run.

### Required And Optional Locales

Required locales are declared by `locale.required` and by any `locale.resources[]` entry with `required: true`.

- If a required selected locale is missing from the manifest, install fails.
- If a required registry locale is not selected by the project, install succeeds and prints a warning naming the skipped required locale and the active selection source.
- If an optional selected locale is missing, install succeeds with a warning.
- If no locale resources match the selected locales but the component declares locale resources, install fails unless only optional locales were requested.

Locale identifiers must use BCP-47 style lower-case language with optional region/script subtags normalized for file matching, such as `en`, `en_US`, `pt_BR`, or `zh_Hant`.

### Ownership

Installed locale files are owned through `.shadcn/components/<component>.json`. The manifest written by the CLI must include:

- `locale.resourcesInstalled`: locale, format, destination path, source path, sha256, and required flag
- `locale.selectionSource`: `project`, `config`, `registryDefault`, or `flag`
- `registryNamespace`
- `registrySourceHash`
- `manifestSource`: `perComponent`, `componentsJson`, or `indexJson`

Update replaces only locale files owned by the same component manifest. Remove deletes locale files only when the installed component manifest owns them and no other installed component manifest references the same destination path.

## Cache Behavior

### Capability Cache

The CLI writes manifest capability cache under `.shadcn/cache/registry-capabilities.json`.

Each cache entry key is:

`<namespace>|<sourceHash>`

`sourceHash` is computed from namespace, effective registry mode, normalized `baseUrl` or local registry root, `paths.componentManifests`, `componentsPath`, `indexPath`, and the latest known ETag values for registry directory and component/index responses. For local registries, the hash uses normalized local path plus file modified timestamps for manifest root, `componentsPath`, and `indexPath`.

Each entry records:

```json
{
  "namespace": "shadcn",
  "sourceHash": "sha256:...",
  "baseUrl": "https://example.com/registry/",
  "componentsPath": "components.json",
  "indexPath": "index.json",
  "componentManifestsPath": "components/{id}.json",
  "manifestSupport": "positive",
  "checkedAt": "2026-05-07T00:00:00Z",
  "etag": "\"abc123\""
}
```

`manifestSupport` is `positive`, `negative`, or `unknown`.

Positive cache means at least one per-component manifest resolved successfully for the registry/source hash. Negative cache means at least one component was requested, the per-component manifest path returned a definitive not-found result, and fallback to `components.json` or `index.json` succeeded or produced a complete not-found answer.

### Invalidation

The CLI must ignore a capability cache entry when any of these values changes:

- namespace
- source hash
- directory ETag
- manifest ETag
- `baseUrl`
- local registry root
- `paths.componentManifests`
- `componentsPath`
- `indexPath`

`--refresh` clears positive and negative manifest capability entries for the command's target registry before resolving components. A global refresh clears all registry capability entries.

### Offline Behavior

Offline mode never probes the network. It may use cached per-component manifests only when manifest support is positive and the specific component manifest body is cached.

If manifest support is negative, offline mode uses cached `components.json` or cached `index.json` according to fallback order. If the required fallback cache is missing, offline mode fails with a clear cache-missing error.

If manifest support is unknown in offline mode, the CLI checks cached per-component manifest bodies first. If no cached per-component manifest exists, it uses cached `components.json`; if that is absent, cached `index.json`; if all are absent or incomplete, it fails. It must not mark the registry negative while offline.

### Force Refresh Behavior

`--refresh` forces online revalidation for directory, per-component manifest, `components.json`, and `index.json` data used by the command. It also clears negative manifest support for the affected registry before probing.

`--force` keeps its existing meaning for destructive or confirmation-skipping flows. It does not imply cache refresh.

## CLI Behavior

### `init`

`flutter_shadcn init` creates or migrates config/state and does not fetch `meta.json`.

`flutter_shadcn init <namespace>` loads and validates `registries.json`, resolves the namespace, respects `minCliVersion`, and executes inline `init.actions` from the registry entry. It does not require per-component manifests, `components.json`, `index.json`, or `meta.json` for bootstrap unless an inline action explicitly references a file index.

`flutter_shadcn locale init` creates the v1 default `l10n.yaml` and locale directory when absent. It refuses to overwrite an existing `l10n.yaml`.

### `add`

Qualified add resolves the named registry first. Unqualified add searches enabled registries. If the component exists in multiple enabled registries, unqualified add fails and instructs the user to use `@namespace/component`.

For each resolved component, `add` loads install metadata in the required fallback order. If a per-component manifest is present, it overrides conflicting `components.json` or `index.json` entries. If only `index.json` is available and incomplete, add fails before writing.

Locale resources are installed only after `l10n.yaml` validation and locale selection. File writes, assets, platform files, and locale files all use existing project path guards.

### `remove`

`remove` uses the installed `.shadcn/components/<component>.json` manifest as the ownership record. It removes files, assets, platform files, and locale resources owned only by that component. It updates `.shadcn/state.json.managedDependencies` using the existing managed dependency behavior.

When the installed manifest is missing, `remove` may use the current registry manifest only to explain what cannot be verified. It must not delete unowned locale files by guessing.

### `sync`

`sync` refreshes installed component metadata using the same fallback order. It preserves installed ownership records when the registry source is unavailable. It updates locale resources only for installed components with recorded locale ownership.

### `doctor`

`doctor` reports:

- manifest capability cache status per enabled registry
- stale positive or negative cache entries
- missing `l10n.yaml` when installed or available components declare locale resources
- invalid `arb-dir`, `template-arb-file`, or `output-localization-file`
- installed locale files missing from disk
- locale files on disk whose ownership conflicts across installed component manifests

### `dry-run`

`dry-run` follows the same source-of-truth order and prints which source would be used: per-component manifest, `components.json`, or `index.json`. It reports selected locales, skipped optional locales, required-locale failures, cache hits, and cache misses. It performs no writes and does not update capability cache unless the command explicitly uses `--refresh`.

### `list`

`list` uses `index.json` for discovery when available. It does not probe every per-component manifest. If no index is available, it may use `components.json`. It reports whether component install metadata is complete only when that information is already in the index or components cache.

### `search`

`search` uses `index.json` first, then `components.json` if no index is available. It does not fetch per-component manifests for search results.

### `info`

`info @namespace/component` resolves the component and loads the per-component manifest first unless the registry has negative manifest support. It then falls back to `components.json` and complete `index.json`. It prints the manifest source, component version, files, dependencies, shared groups, platform metadata, locale resources, and hashes.

### `add`, `info`, And `dry-run` Cache Side Effects

Successful per-component manifest fetch sets manifest support positive for the registry/source hash. A definitive not-found response for a requested per-component manifest sets support negative only after fallback succeeds or after fallback proves the component does not exist. Transient network failures do not set negative support.

## What To Do

1. Extend registry directory model and schema handling with optional `paths.componentManifests`.
2. Add component manifest model classes for identity, files, shared, dependencies, pubspec, assets, post-install, platform, locale, and hashes.
3. Add a component install-source resolver that returns both the resolved component model and `manifestSource`.
4. Add registry capability cache read/write/invalidation under `.shadcn/cache/registry-capabilities.json`.
5. Update add/info/dry-run/sync to use the install-source resolver.
6. Keep list/search index-first and prevent per-result manifest probes.
7. Add `flutter_shadcn locale init`.
8. Add l10n.yaml parser and locale selection service.
9. Extend installed component manifests with locale ownership, registry namespace/source hash, and manifest source.
10. Preserve `.shadcn/state.json.managedDependencies` behavior during add, remove, and sync.
11. Keep path traversal and symlink escape checks on all writes, including locale resources.

## Edge Cases To Resolve

| Edge case | Resolution |
| --- | --- |
| Per-component manifest exists and conflicts with `components.json` | Use per-component manifest. Report conflict only in `doctor`; install proceeds from manifest. |
| Per-component manifest returns 404 | Fall back to `components.json`; if component exists there, set negative manifest support for the registry/source hash. |
| Per-component manifest fetch fails with timeout or 5xx | Do not set negative support. Use cached manifest if valid; otherwise fall back only if cache rules allow. |
| Registry has negative manifest support | Skip per-component manifest probes until invalidation or `--refresh`. |
| Registry source hash changes | Ignore old capability cache and probe manifests again. |
| `components.json` missing and manifest support negative | Use `index.json` only if the entry has complete install metadata; otherwise fail. |
| `index.json` has only search metadata | Fail install with "index.json entry for <component> lacks install metadata; cannot install without per-component manifest or components.json." |
| Unqualified component exists in two enabled registries | Fail and require `@namespace/component`. |
| Qualified component does not exist in target registry but exists elsewhere | Fail for the requested namespace and suggest the matching qualified address only if known from cached discovery. |
| Offline with cached per-component manifest | Use cached manifest and validate hashes where present. |
| Offline with negative manifest support and cached `components.json` | Use cached `components.json`. |
| Offline with unknown manifest support and no cached manifest | Try cached `components.json`, then cached complete `index.json`; do not update capability cache. |
| `--refresh` with stale negative cache | Clear negative cache before probing. |
| Missing `l10n.yaml` and component has locale resources | Fail with the `flutter_shadcn locale init` error before writing files. |
| Existing `l10n.yaml` has no `arb-dir` | Fail with a clear configuration error. |
| Existing `l10n.yaml` has `arb-dir` escaping project root | Reject through project path guard. |
| ARB file is malformed JSON | Fail before writing that locale resource. |
| ARB metadata has placeholders or examples | Preserve metadata exactly. |
| JSON locale file is an array or scalar | Fail because v1 JSON locale resources must be objects. |
| Required selected locale missing | Fail before writing. |
| Optional selected locale missing | Warn and continue. |
| Required registry locale not selected by project/config/flag | Warn and continue. |
| Locale destination conflicts with another component owner | Do not overwrite; fail unless both manifests reference the same source hash and content hash. |
| Remove sees missing installed component manifest | Do not delete guessed locale files; report missing ownership record. |
| Component manifest lists a destination outside project root | Reject via project path guard. |
| Component manifest source path contains traversal or URL fragment | Reject via resolver rules. |
| Manifest `id` differs from requested id | Fail and do not fall back silently. |
| Manifest hash mismatch | Fail; `--skip-integrity` may bypass only developer integrity validation, not unsafe path validation. |
| Legacy single-registry config lacks `registries` map | Auto-migrate before resolving registry source. |
| `meta.json` unavailable during init | Init still succeeds unless an inline action explicitly fetches an unavailable file it owns. |

## Tests

- Unit test per-component manifest path template validation and id replacement.
- Unit test fallback order: manifest wins over `components.json`, `components.json` wins over complete `index.json`.
- Unit test incomplete `index.json` install failure.
- Unit test positive manifest support cache prevents fallback-first behavior.
- Unit test negative manifest support skips later probes for same namespace/source hash.
- Unit test invalidation on ETag, `baseUrl`, `componentManifests`, and `componentsPath` changes.
- Unit test offline behavior for positive, negative, and unknown manifest support.
- Unit test `--refresh` clears negative cache and probes again.
- Unit test unqualified add ambiguity across enabled registries.
- Unit test missing `l10n.yaml` fails for locale-aware components.
- Unit test `flutter_shadcn locale init` creates default `l10n.yaml` and `lib/l10n/`.
- Unit test existing `l10n.yaml` is not overwritten.
- Unit test locale selection precedence: project, config override, registry default.
- Unit test no silent all-locale install.
- Unit test required and optional locale warning/error matrix.
- Unit test ARB metadata preservation and malformed ARB rejection.
- Unit test JSON locale object requirement.
- Unit test locale write path traversal and symlink escape rejection.
- Unit test add/update/remove locale ownership in installed component manifests.
- Unit test `.shadcn/state.json.managedDependencies` remains unchanged except for existing dependency sync semantics.
- End-to-end fixture test for registry with per-component manifests.
- End-to-end fixture test for registry without per-component manifests using negative cache on the second command.
- End-to-end fixture test for fallback to complete `index.json`.
