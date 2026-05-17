# Manifest-Contract-Driven CLI — Production Readiness Gap Analysis
Prepared for inclusion in: `docs/superpowers/plans/2026-05-04-registry-scalability-remediation.md`
Status: BLOCKING — all P0 gaps must be resolved before CLI ships to any consumer

---

## How to Use This Document

Gaps are rated by severity:

| Rating | Meaning |
|--------|---------|
| 🔴 P0 — Hard Blocker | Will cause data loss, security vulnerability, or broken installs at runtime. Cannot ship. |
| 🟠 P1 — Soft Blocker | Will cause incorrect behaviour or consumer confusion at scale. Must fix before stable release. |
| 🟡 P2 — Risk | Will cause pain in edge cases or under load. Fix before calling the CLI production-grade. |
| 🔵 P3 — Design Debt | Leaves a door open that will hurt later. Address before v2. |

Total gaps found: **27**
Hard blockers: **9**
Soft blockers: **9**
Risks: **6**
Design debt: **3**

---

## CATEGORY 1 — Security Gaps

### GAP-01 🔴 P0 — Path Traversal Attack Surface

**What the document says:**
> "The path can be anything. The registry owner decides the structure."

**The problem:**
A malicious or compromised registry can declare:
```json
{
  "source": "../../.ssh/id_rsa",
  "target": "lib/components/button.dart"
}
```
or worse:
```json
{
  "target": "../../pubspec.yaml"
}
```

The CLI will happily overwrite files outside the project or exfiltrate system files if it follows manifest paths without sanitisation. This is a zero-day on any machine that runs an install from an untrusted registry.

**Required fix:**
- All `source` paths must be validated to be relative and must not escape the registry root. Reject any path containing `..`.
- All `target` paths must be validated to be relative and must not escape the consumer project root. Reject any path containing `..`.
- Add an allowlist of permitted target root directories: `lib/`, `assets/`, `test/`. Refuse any target outside these.
- This validation must run before any file operation, not after.

---

### GAP-02 🔴 P0 — No Registry Authentication or Trust Model

**What the document says:**
Nothing. Registry URLs are assumed to be trusted.

**The problem:**
The CLI fetches manifests from remote registries. There is no mechanism to:
- Verify the manifest came from a legitimate registry owner
- Detect tampering of a manifest in transit
- Prevent a DNS hijack from pointing `flutter_shadcn_kit` at a malicious registry
- Warn users before executing install operations from a registry they have not explicitly trusted

**Required fix:**
- Registries must be explicitly added to a local trust store before the CLI will install from them: `shadcn add-registry <url>`.
- The trust store records the registry URL and optionally a public key or checksum for manifest verification.
- HTTPS must be required for all remote registry URLs. HTTP must be rejected.
- Consider signing manifests and verifying signatures before install, at minimum for the official registry.

---

### GAP-03 🟠 P1 — No Sandboxing of Install Targets by Registry

**What the document says:**
Multiple registries can all target `lib/l10n/shadcn/en.json`.

**The problem:**
Registry A declares `"target": "lib/main.dart"`. Even with path traversal protection, a malicious registry can overwrite critical project files that are inside the project root. There is no per-registry isolation of where files can be installed.

**Required fix:**
- Define a per-registry install scope. Default scope: `lib/components/<registryId>/` for Dart files, `assets/<registryId>/` for assets, `lib/l10n/shadcn/` for l10n merges only.
- The CLI must warn and require explicit confirmation for any install target outside the default scope.

---

## CATEGORY 2 — Protocol and Schema Gaps

### GAP-04 🔴 P0 — Schema Versioning Has No Compatibility Contract

**What the document says:**
```json
{ "schemaVersion": "1.0.0" }
```

**The problem:**
The version field exists but has no defined behaviour. When the CLI is on schema v2 and a registry is still on v1:
- Does the CLI refuse to install?
- Does it attempt a best-effort migration?
- Does it silently ignore unknown fields?
- Does it crash?

None of this is defined. At scale with multiple registry authors on different versions, this will cause unpredictable install behaviour.

**Required fix:**
- Define a compatibility matrix: which CLI versions can read which schema versions.
- Define the upgrade path: when a schema field is removed or renamed, what is the deprecation window?
- CLI must check `schemaVersion` as the first operation after reading any manifest. Unknown or unsupported versions must produce a clear error, not a silent failure.
- Document the schema as a versioned spec, not as example JSON.

---

### GAP-05 🔴 P0 — No Manifest Validation Before Install

**What the document says:**
The CLI reads the manifest and follows it.

**The problem:**
There is no step where the CLI validates the manifest structure before executing installs. A manifest with a missing `target` field, a wrong type, a null `source`, or an invalid `mergeStrategy` value will cause the CLI to fail mid-install, potentially leaving the consumer project in a partially modified state.

**Required fix:**
- The CLI must validate the full manifest against a JSON Schema before any file operation begins.
- Validation must be a dry-run gate: if validation fails, zero files are touched.
- Emit a structured validation report listing every field violation before aborting.

---

### GAP-06 🔴 P0 — No Transactional Install — Partial Failure Leaves Broken State

**What the document says:**
Nothing about what happens when an install fails midway.

**The problem:**
Installing a component copies 5 files, merges 2 l10n files, and modifies pubspec.yaml. If it fails on step 4, the consumer project has:
- 3 partially copied Dart files (some of which may reference symbols from the uncopied files)
- A modified pubspec.yaml
- A partially merged l10n file
- No way to automatically recover

**Required fix:**
- Install must be transactional: stage all changes in a temp location, then commit atomically, or record a rollback manifest before starting.
- On failure, the CLI must restore all modified files to their pre-install state automatically.
- A `shadcn install --dry-run` mode must be implemented that previews all changes without touching any files. This must be available before stable release.

---

### GAP-07 🟠 P1 — Component IDs Are Not Globally Namespaced

**What the document says:**
```json
{ "id": "button" }
```
Used in both `flutter_shadcn_kit` and `acme_ui`.

**The problem:**
When a consumer has installed `button` from two different registries, the CLI has no way to distinguish them using only the `id` field. Commands like `shadcn update button` or `shadcn remove button` are ambiguous. The lockfile (which does not exist yet — see GAP-14) would need to track `registryId + componentId` as a composite key.

**Required fix:**
- All internal CLI operations must key components as `<registryId>/<componentId>`, never bare `<componentId>`.
- CLI commands must support qualified IDs: `shadcn install flutter_shadcn_kit/button`.
- Bare IDs must only be accepted when a single matching component exists across all configured registries, and must error if ambiguous.

---

### GAP-08 🟠 P1 — `pick_keys_preserve_user` Strategy Is Ambiguous

**What the document says:**
```json
{
  "mergeStrategy": "pick_keys_preserve_user",
  "keys": ["acme.calendar.today", "acme.calendar.nextMonth"]
}
```

**The problem:**
The key notation `"acme.calendar.today"` is undefined. Does it mean:
- A flat JSON key literally named `"acme.calendar.today"`?
- A dot-notation path into a nested object: `{ "acme": { "calendar": { "today": "..." } } }`?

These are two completely different data structures and two completely different lookup implementations. The document uses both dot-notation (for namespacing) and the `keys` array (for picking), creating ambiguity about whether the source JSON is flat or nested.

**Required fix:**
- Explicitly define the key notation. Recommend: dot-notation paths into nested JSON objects.
- Define what happens when a declared key does not exist in the source file: error or skip?
- Define what happens when a declared key exists in the target but not the source on update: keep or remove?

---

### GAP-09 🟠 P1 — Capability Flags Create a Second Source of Truth

**What the document says:**
```json
{
  "capabilities": { "localization": true, "assets": true }
}
```
Then immediately: "do not rely only on the flags. The actual install data should still be declared per component."

**The problem:**
If the actual install data is authoritative and flags are advisory, the flags can diverge from reality. A registry that sets `"localization": false` but declares localization resources per component will confuse the CLI and any tooling that reads the manifest. Two sources of truth will always drift.

**Required fix:**
- Remove registry-level capability flags entirely. Capabilities are implied by the presence or absence of resource declarations per component.
- If capability flags are kept for UI/discovery purposes (e.g. a registry browser), they must be derived and generated from component data, never hand-authored.

---

### GAP-10 🟠 P1 — Uninstall and Update Paths Are Completely Missing

**What the document says:**
The entire document covers only installation.

**The problem:**
This is the largest single gap in the design. A production CLI must answer all three questions:

**Install:** Copy files, merge l10n keys, modify pubspec — designed.
**Update:** What happens when a registry ships a new version of button?
- Which files get overwritten? All of them? Only unchanged ones?
- What happens to l10n keys the user has customised?
- What happens to new keys added in the update?

**Uninstall:** What happens when a consumer removes button?
- Which Dart files get deleted? (Easy — they are declared in `files`)
- Which l10n keys get removed from the merged `en.json`? (Hard — the CLI must know which keys were originally installed by this component)
- What if the user modified those keys? Do they get removed anyway?
- What happens to pubspec.yaml dependencies that were added for this component but are also used by another installed component?

None of this is designed.

**Required fix:**
- Design the update contract before shipping. Minimum viable: `shadcn update <component>` re-copies source files and re-merges l10n using the configured merge strategy.
- Design the uninstall contract. Minimum viable: the lockfile (GAP-14) records which keys were installed by which component. Uninstall removes only those keys.
- Shared dependencies (pubspec packages, shared components) must be reference-counted. A dependency is removed from pubspec only when the last component that declared it is uninstalled.

---

### GAP-11 🟠 P1 — `required: false` Creates Silent Runtime Failures

**What the document says:**
```json
{ "required": false }
```
If the resource is missing, the CLI continues.

**The problem:**
A localization resource marked `required: false` that is missing at install time will cause a runtime `null` or key-not-found error when the component tries to look up a translation string. The install succeeds but the component is broken. This is worse than a failed install because it is invisible until the user triggers the missing translation path.

**Required fix:**
- `required: false` should mean: "skip this resource silently at install time but emit a warning."
- The warning must include: "Component X installed without localization for locale Y. Strings will fall back to key names at runtime."
- The CLI must record missing optional resources in the lockfile so `shadcn doctor` can surface them.

---

## CATEGORY 3 — Flutter-Specific Gaps

### GAP-12 🔴 P0 — ARB Format Merge Is Not the Same as JSON Merge

**What the document says:**
```json
{ "format": "arb" }
```
Listed as a supported format alongside JSON.

**The problem:**
Flutter's standard localisation format is ARB (Application Resource Bundle), not JSON. ARB files look like JSON but have special semantics:
- Keys prefixed with `@` are metadata, not translatable strings: `"@buttonLabel": { "description": "..." }`
- `@@locale` is a required top-level key
- `@@last_modified` is commonly present
- Metadata keys must travel with their associated string key

A `deep_merge_preserve_user` applied naively to ARB will:
- Drop `@` metadata keys if they are not in the target
- Duplicate `@@locale` declarations if both source and target have it
- Produce an ARB file that fails Flutter's `gen-l10n` validation

**Required fix:**
- Implement ARB-aware merge as a distinct operation from JSON merge.
- ARB merge rules: copy string keys and their associated `@` metadata keys together as a unit. Never merge `@@locale` or `@@last_modified` — always derive from context. Validate the output against ARB schema before writing.
- Document clearly whether the official registry uses ARB or JSON internally and commit to one format for the `flutter_shadcn_kit` registry.

---

### GAP-13 🔴 P0 — Target l10n Path Ignores Consumer Project's `l10n.yaml`

**What the document says:**
```json
{ "target": "lib/l10n/shadcn/en.json" }
```
Hardcoded target path in the manifest.

**The problem:**
Flutter projects configure their localisation directory in `l10n.yaml`:
```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```

A consumer project may have `arb-dir: lib/i18n` or `arb-dir: assets/l10n`. The manifest's hardcoded target path will put files in the wrong location. Flutter's `gen-l10n` will not pick them up. The component will have broken localisation silently.

**Required fix:**
- The CLI must read the consumer project's `l10n.yaml` before resolving any l10n target paths.
- The `target` field in the manifest should be treated as a relative path within the consumer's configured `arb-dir`, not an absolute project path.
- If no `l10n.yaml` exists, the CLI must prompt the consumer to configure it or create a minimal one, not guess.

---

### GAP-14 🟠 P1 — No Lockfile — Reproducible Builds Are Impossible

**What the document says:**
Nothing. There is no lockfile concept.

**The problem:**
Without a lockfile, there is no record of:
- Which registry each installed component came from
- Which version of each component was installed
- Which files were copied and to which paths
- Which l10n keys were added by which component
- Which pubspec dependencies were added for which component

This means:
- Two developers on the same project may have different component versions installed
- CI builds are not reproducible
- Uninstall and update operations have no source of truth
- `shadcn doctor` cannot verify install integrity

**Required fix:**
- Implement `shadcn.lock` committed to the project repo. Minimum viable schema:
```json
{
  "lockfileVersion": "1.0.0",
  "installedComponents": [
    {
      "qualifiedId": "flutter_shadcn_kit/button",
      "registryId": "flutter_shadcn_kit",
      "componentId": "button",
      "installedAt": "2026-05-04T14:32:00Z",
      "sourceManifestHash": "<sha256>",
      "installedFiles": ["lib/components/ui/button/button.dart"],
      "installedL10nKeys": {
        "lib/l10n/shadcn/en.json": ["flutter_shadcn_kit.button.label", "flutter_shadcn_kit.button.loading"]
      },
      "addedPubspecDependencies": ["intl"]
    }
  ]
}
```

---

### GAP-15 🟡 P2 — pubspec.yaml Dependency Modification Is Fragile

**What the document says:**
```json
{ "pubspec": { "dependencies": { "intl": "^0.20.0" } } }
```

**The problem:**
Programmatically modifying `pubspec.yaml` is non-trivial:
- YAML preserves comments; most YAML parsers drop them on round-trip
- A consumer may have `intl: ^0.19.0` pinned for a reason. Overwriting with `^0.20.0` may break other parts of their project.
- Version conflicts between two components requiring different versions of the same package are not handled.
- There is no conflict resolution strategy: last-write-wins, fail on conflict, or prompt the user.

**Required fix:**
- The CLI must never silently overwrite an existing version constraint. If the consumer has `intl: ^0.19.0` and the component requires `^0.20.0`, the CLI must warn and present options: keep existing, upgrade, or abort.
- Use a YAML library that preserves comments on round-trip, or write only to a clearly delimited section of pubspec.yaml.
- Implement reference counting for added dependencies so they are only removed on uninstall when no other installed component depends on them.

---

### GAP-16 🟡 P2 — Locale Filtering and Fallback Strategy Is Undefined

**What the document says:**
Registries declare locales. The CLI installs them.

**The problem:**
- A registry has en, ur, ar, fr, de. The consumer project only needs en and ur. All 5 locales will be installed.
- A registry has only en. The consumer project needs en and ur. The ur strings are silently missing. No warning is emitted.
- A registry updates and adds a new locale es. Does it get auto-installed on next update?

**Required fix:**
- The CLI must read the consumer project's supported locales (from `l10n.yaml` or a project config) and install only matching locales.
- If a required locale is not available in the registry, emit a warning — not a silent skip.
- On update, new locales must not be auto-installed. They must be listed and require explicit opt-in.

---

### GAP-17 🟡 P2 — Circular Shared Dependencies Have No Detection

**What the document says:**
```json
{ "shared": ["overlay", "form_control", "l10n_runtime"] }
```

**The problem:**
`overlay` may depend on `form_control`. `form_control` may depend on `overlay`. The CLI has no cycle detection. This will produce infinite recursion or a stack overflow during dependency resolution.

**Required fix:**
- The CLI must build a dependency graph before resolving installs.
- Cycle detection must run on the graph before any file operations begin.
- On cycle detected: abort with a clear error listing the cycle path.

---

### GAP-18 🟡 P2 — No Component Version Pinning

**What the document says:**
```json
{ "id": "button" }
```
No version field on components.

**The problem:**
A registry can silently ship breaking changes to button. Every consumer who runs `shadcn update` will get the breaking version with no way to pin to the previous version. This makes the CLI unsuitable for production apps where stability is required.

**Required fix:**
- Add a `version` field to component declarations in the manifest.
- The lockfile must record which version was installed.
- `shadcn install flutter_shadcn_kit/button@1.2.0` must be supported.
- `shadcn update` must show a diff of what will change before applying.

---

### GAP-19 🟡 P2 — Asset Merge Semantics Are Undefined

**What the document says:**
```json
{ "source": "icon.svg", "target": "assets/shadcn/icons/icon.svg", "pubspec": true }
```

**The problem:**
- `"pubspec": true` means add to `flutter.assets` in pubspec.yaml — but what format? Does it add the individual file path or the directory?
- What happens if the target asset already exists (user has customised it)?
- What happens on component update — does the asset get overwritten?
- Binary assets cannot be merged. The strategy options (`deep_merge_preserve_user`) that apply to JSON do not apply to SVG, PNG, or font files. Applying the wrong strategy to binary assets is undefined behaviour.

**Required fix:**
- Assets must use only `copy` or `copy_preserve_user` strategies. Deep merge must be explicitly rejected for non-text files.
- `copy_preserve_user`: if the target file exists, skip and warn. `copy`: always overwrite.
- Define the exact pubspec.yaml modification: individual path (`assets/shadcn/icons/icon.svg`) not directory.

---

## CATEGORY 4 — CLI Behaviour Gaps

### GAP-20 🔴 P0 — No CLI Command Specification

**What the document says:**
Nothing. The document designs data shapes only.

**The problem:**
The entire document is about manifest schema. There are zero CLI commands defined. A user reading this cannot answer:
- How do I install a component?
- How do I add a registry?
- How do I update a component?
- How do I remove a component?
- How do I check what is installed?
- How do I see what would change before I commit to an install?

**Required fix:**
Define the minimum viable command surface before any implementation begins:

```
shadcn add-registry <url>              Add and trust a registry
shadcn list-registries                 Show trusted registries
shadcn search <query>                  Search components across registries
shadcn install <registryId/componentId>[@version]   Install a component
shadcn install --dry-run               Preview changes without touching files
shadcn update [registryId/componentId] Update installed components
shadcn remove <registryId/componentId> Uninstall a component
shadcn list                            List installed components
shadcn doctor                          Verify install integrity against lockfile
shadcn sync                            Re-apply lockfile state (for CI/onboarding)
```

---

### GAP-21 🟠 P1 — `shadcn sync` / CI Reproducibility Path Is Missing

**What the document says:**
Nothing about CI or team onboarding.

**The problem:**
When a new developer clones the project or CI runs a fresh build, there is no command to reproduce the installed component state from the lockfile. Without this, copy-paste components must be committed to the repo (which they currently are), making the CLI value proposition unclear.

**Required fix:**
- `shadcn sync` must read `shadcn.lock` and reinstall all components to their locked versions from their declared registries.
- This is the equivalent of `flutter pub get` for registry components.
- Document whether components are committed to the repo or gitignored and restored via `shadcn sync`. This is a fundamental design decision that affects every consumer's git workflow.

---

### GAP-22 🟠 P1 — `shadcn doctor` Is Referenced But Not Designed

**What the document says:**
Referenced implicitly but never defined.

**The problem:**
A `doctor` command is the standard way CLI tools surface integrity problems. Without it, consumers have no way to detect:
- Files that have drifted from the installed manifest (local edits)
- Missing optional localization resources
- pubspec.yaml dependencies that were removed manually
- Components in the lockfile that are no longer installed on disk

**Required fix:**
Define the minimum `shadcn doctor` checks:
- For each component in lockfile: verify declared files exist at declared targets
- For each l10n key in lockfile: verify key exists in target l10n file
- For each pubspec dependency in lockfile: verify it exists in pubspec.yaml
- Report status per component: `✅ OK`, `⚠️ MODIFIED`, `❌ MISSING`

---

## CATEGORY 5 — Design Debt

### GAP-23 🔵 P3 — Post-Install Notes Are a Placeholder, Not a Design

**What the document says:**
> "post-install notes" listed in the install unit concept.

**The problem:**
Post-install notes are one of the most important parts of a copy-paste CLI. Components often require manual steps: registering a theme, adding a delegate to MaterialApp, configuring an initialiser. If the CLI cannot surface these clearly and track whether they have been completed, consumers will silently ship broken integrations.

**Required fix:**
Define a `postInstall` schema before v1:
```json
{
  "postInstall": {
    "notes": ["Register the theme global: registerButtonThemeGlobals()"],
    "requiredManualSteps": true
  }
}
```
CLI must display these notes after every install and store them in the lockfile so `shadcn doctor` can remind the user if steps are marked required.

---

### GAP-24 🔵 P3 — `config patches` Are a Placeholder, Not a Design

**What the document says:**
> "config patches" listed in the install unit concept.

**The problem:**
Config patches — modifying `main.dart`, `MaterialApp`, `l10n.yaml`, or `pubspec.yaml` — are the highest-risk operations a CLI can perform. Patching code files is fragile and can corrupt consumer projects. This is listed as a feature without any design, safety model, or opt-in mechanism.

**Required fix:**
Either commit to a design (patch format, safety model, dry-run requirement, rollback) or explicitly remove `config patches` from the install unit concept until it can be designed properly. Do not ship a feature name with no implementation contract.

---

### GAP-25 🔵 P3 — Namespace Uniqueness Is Unenforceable Without a Registry Coordinator

**What the document says:**
> "Use namespaced keys to prevent conflicts across registries."

**The problem:**
Namespaces only prevent conflicts if they are unique. `flutter_shadcn_kit` can use `flutter_shadcn_kit.button.label`. `acme_ui` can also claim `flutter_shadcn_kit.button.label` and there is no enforcement mechanism. There is no registry coordinator, no namespace reservation system, and no CLI-side conflict detection at install time.

**Required fix:**
- The CLI must detect namespace collisions at install time by comparing the `namespace` fields of all installed components.
- On collision: warn the user and list both components claiming the same namespace. Do not silently overwrite.
- Longer term: document that namespace is the registry owner's responsibility, and that `registryId` must be part of the namespace by convention: `<registryId>.<componentId>.<key>`.

---

## Summary — Prioritised Fix Order

### Must fix before any consumer-facing release (P0)
| Gap | Title |
|-----|-------|
| GAP-01 | Path traversal attack surface |
| GAP-02 | No registry authentication or trust model |
| GAP-04 | Schema versioning has no compatibility contract |
| GAP-05 | No manifest validation before install |
| GAP-06 | No transactional install — partial failure leaves broken state |
| GAP-12 | ARB format merge is not the same as JSON merge |
| GAP-13 | Target l10n path ignores consumer project's l10n.yaml |
| GAP-20 | No CLI command specification |

### Must fix before stable release (P1)
| Gap | Title |
|-----|-------|
| GAP-03 | No sandboxing of install targets by registry |
| GAP-07 | Component IDs are not globally namespaced |
| GAP-08 | pick_keys_preserve_user strategy is ambiguous |
| GAP-09 | Capability flags create a second source of truth |
| GAP-10 | Uninstall and update paths are completely missing |
| GAP-11 | required: false creates silent runtime failures |
| GAP-14 | No lockfile — reproducible builds are impossible |
| GAP-21 | shadcn sync / CI reproducibility path is missing |
| GAP-22 | shadcn doctor is referenced but not designed |

### Fix before calling the CLI production-grade (P2)
| Gap | Title |
|-----|-------|
| GAP-15 | pubspec.yaml dependency modification is fragile |
| GAP-16 | Locale filtering and fallback strategy is undefined |
| GAP-17 | Circular shared dependencies have no detection |
| GAP-18 | No component version pinning |
| GAP-19 | Asset merge semantics are undefined |

### Address before v2 (P3)
| Gap | Title |
|-----|-------|
| GAP-23 | Post-install notes are a placeholder, not a design |
| GAP-24 | config patches are a placeholder, not a design |
| GAP-25 | Namespace uniqueness is unenforceable |

---

## Definition of Done for CLI v1

The CLI is ready for a production consumer release when:

- [ ] Path traversal validation runs before every install operation
- [ ] Registry trust store exists and is required before install
- [ ] Manifest is validated against a JSON Schema before any file is touched
- [ ] Install is transactional with automatic rollback on failure
- [ ] `--dry-run` mode previews all changes without touching files
- [ ] `shadcn.lock` is generated and committed
- [ ] ARB-aware merge is implemented and tested separately from JSON merge
- [ ] Consumer project's `l10n.yaml` is read and respected before any l10n target path is resolved
- [ ] All CLI commands are defined and documented
- [ ] `shadcn sync` restores lockfile state from scratch
- [ ] `shadcn doctor` reports component integrity status
- [ ] Uninstall removes only lockfile-tracked files and keys
- [ ] Update shows a change diff before applying
- [ ] Component IDs are qualified by registryId in all internal operations

---

*Gap analysis complete. 27 gaps identified. 8 are hard blockers that will cause security vulnerabilities, data loss, or broken installs if shipped without resolution.*
