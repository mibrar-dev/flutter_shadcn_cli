# `registries.json` Reference

`registries.json` is the registry directory. It tells the CLI which registries exist, where their component manifests live, what namespace they install under, and which bootstrap actions run during `init`.

Published registries are validated against the registry directory schema before public install, init, and add flows continue.

## Top-Level Shape

```json
{
  "schemaVersion": 1,
  "registries": []
}
```

Fields:

- `schemaVersion`: registry directory schema version
- `registries`: list of registry entries

## Registry Entry

Required identity fields:

- `id`: stable registry identifier
- `displayName`: human-readable registry name
- `maintainers`: list of maintainers
- `repo`: source repository URL
- `license`: registry license
- `minCliVersion`: minimum CLI version required by the registry

Required resolution fields:

- `baseUrl`: base URL used to fetch registry files
- `paths.componentsJson`: component manifest path, usually `components.json`
- `install.namespace`: namespace used in component addresses
- `install.root`: project-relative install root, usually under `lib/`

Recommended path fields:

- `paths.componentsSchemaJson`: schema for `components.json`
- `paths.indexJson`: list/search index
- `paths.indexSchemaJson`: schema for the index
- `paths.themesJson`: theme catalog
- `paths.themesSchemaJson`: schema for themes
- `paths.themeConverterDart`: deprecated legacy field. Current CLI builds do not use it.
- `paths.folderStructureJson`: optional folder structure metadata
- `paths.metaJson`: optional registry metadata

Capability fields:

- `capabilities.sharedGroups`: registry can publish reusable shared groups
- `capabilities.composites`: registry can publish composite components
- `capabilities.theme`: registry supports theme commands

Trust fields:

- `trust.mode`: `none` or `sha256`
- `trust.sha256`: expected SHA-256 hex digest when `mode` is `sha256`

Example:

```json
{
  "id": "official",
  "displayName": "Official",
  "maintainers": ["shadcn_flutter"],
  "repo": "https://github.com/example/registry",
  "license": "MIT",
  "minCliVersion": "0.2.0",
  "baseUrl": "https://example.com/registry/",
  "paths": {
    "componentsJson": "components.json",
    "componentsSchemaJson": "components.schema.json",
    "indexJson": "index.json",
    "indexSchemaJson": "index.schema.json",
    "themesJson": "themes.json",
    "themesSchemaJson": "themes.schema.json"
  },
  "install": {
    "namespace": "shadcn",
    "root": "lib/ui/shadcn"
  },
  "capabilities": {
    "sharedGroups": true,
    "composites": true,
    "theme": true
  },
  "trust": {
    "mode": "sha256",
    "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  },
  "init": {
    "version": 1,
    "actions": []
  }
}
```

## Path Rules

Registry paths are relative to `baseUrl`. The CLI rejects paths that are absolute, empty, escape with `..`, or contain unsupported URL fragments.

`install.root` is project-relative. Published registries should install under `lib/` so generated code is part of the Flutter project source tree.

For `copyFiles` init actions, files are treated as relative to the action `base` when `base` and `destBase` are present. The official registry uses paths relative to that base, so the CLI maps those paths without requiring the base prefix inside each file entry.

## Theme Artifacts

Each registry owns its theme format and generation pipeline. Conversion should happen at registry publish time. The CLI consumes only pre-generated, hash-verified theme artifacts.

When a registry supports themes, its published theme data should resolve to artifacts and manifests that are already generated for CLI consumption. The CLI does not perform theme conversion at apply time.

## Inline Init

`init.version` must be `1`. `init.actions` is executed by `flutter_shadcn init <namespace>` after the registry is resolved and validated.

Supported actions are documented in [inline-init-actions.md](inline-init-actions.md).

Registries cannot publish arbitrary config or code patches through inline init.
Fields such as `configPatches`, `patches`, `mainDartPatch`, and generic
`modifyFile` actions are rejected during schema/preflight validation before any
file write. Platform-specific component manifest sections and `mergePubspec`
remain the supported extension points for platform and pubspec changes.

## Validation Behavior

Public install, init, and add flows fail when the registry directory or registry manifests do not match their schema. Developer-only integrity bypass is documented in [../developer/integrity-and-schema-validation.md](../developer/integrity-and-schema-validation.md).
