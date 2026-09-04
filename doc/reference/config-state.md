# Config and State Reference

The CLI stores project configuration in `.shadcn/config.json` and command state in `.shadcn/state.json`. Both files are project-local. They are created by `flutter_shadcn init` and updated by registry, install, remove, theme, platform, and dependency commands.

Installed v1 component source records are stored in `shadcn.lock`. Per-component install manifests are stored under `.shadcn/components/`.

## `.shadcn/config.json`

`config.json` describes how the CLI should resolve registries and where generated files should be written.

Common top-level fields:

- `defaultNamespace`: registry namespace used when a command does not specify `@namespace/component`
- `registries`: map of namespace to registry configuration
- `installPath`: active registry install root
- `sharedPath`: active registry shared file root
- `includeReadme`: include component README files when available
- `includeMeta`: include component metadata files when available
- `includePreview`: include preview/example files when available
- `includeFiles`: optional file kinds to include
- `excludeFiles`: optional file kinds to exclude
- `pathAliases`: generated alias map
- `platformTargets`: platform-specific target map
- `themeId`: selected theme identifier
- `classPrefix`: generated class prefix
- `checkUpdates`: enables update checks when supported

Example:

```json
{
  "defaultNamespace": "shadcn",
  "registries": {
    "shadcn": {
      "registryMode": "remote",
      "baseUrl": "https://example.com/registry/",
      "componentsPath": "components.json",
      "componentsSchemaPath": "components.schema.json",
      "installPath": "lib/ui/shadcn",
      "sharedPath": "lib/ui/shadcn/shared",
      "includePreview": false,
      "enabled": true
    }
  }
}
```

## Registry Entries

Each `registries` entry is keyed by namespace.

Resolution fields:

- `registryMode`: `remote` or `local`
- `registryPath`: local registry path for development
- `registryUrl`: registry URL override
- `baseUrl`: base URL used to fetch registry assets
- `enabled`: whether this registry participates in resolution

Registry file fields:

- `componentsPath`: component manifest path
- `componentsSchemaPath`: component schema path
- `indexPath`: registry search/list index path
- `indexSchemaPath`: index schema path
- `themesPath`: themes manifest path
- `themesSchemaPath`: themes schema path
- `folderStructurePath`: folder structure metadata path
- `metaPath`: optional registry metadata path
- `themeConverterDartPath`: deprecated legacy field. It is ignored by current CLI builds.

Install fields:

- `installPath`: component install root
- `sharedPath`: shared file install root
- `includeReadme`: default README inclusion behavior
- `includeMeta`: default metadata inclusion behavior
- `includePreview`: default preview inclusion behavior
- `includeFiles`: file kinds included by default
- `excludeFiles`: file kinds excluded by default

Capability and trust fields:

- `capabilitySharedGroups`: registry supports shared groups
- `capabilityComposites`: registry supports composite components
- `capabilityTheme`: registry supports theme commands
- `trustMode`: integrity mode, such as `none` or `sha256`
- `trustSha256`: expected SHA-256 digest for the registry directory entry

Theme artifact rule:

Each registry owns its theme format and generation pipeline. Conversion should happen at registry publish time. The CLI consumes only pre-generated, hash-verified theme artifacts.

## `.shadcn/state.json`

`state.json` records what the CLI has installed or selected. It is not a substitute for source control; it is used by the CLI to make future commands consistent.

Common fields:

- `defaultNamespace`: resolved default namespace
- `registries`: per-registry state map
- `installPath`: active install path fallback
- `sharedPath`: active shared path fallback
- `themeId`: selected theme fallback
- `managedDependencies`: packages currently managed by installed components

Example:

```json
{
  "installPath": "lib/ui/shadcn",
  "sharedPath": "lib/ui/shadcn/shared",
  "themeId": "default",
  "managedDependencies": ["collection"],
  "defaultNamespace": "shadcn",
  "registries": {
    "shadcn": {
      "installPath": "lib/ui/shadcn",
      "sharedPath": "lib/ui/shadcn/shared",
      "themeId": "default"
    }
  }
}
```

Per-registry state fields:

- `installPath`: last known install root for the registry
- `sharedPath`: last known shared root for the registry
- `themeId`: selected theme for the registry

## Normalization

Valid older-shaped config and state files are normalized on load. The CLI keeps their meaning, writes the current shape back to disk, and continues the command.

Missing files are treated as empty defaults. Invalid JSON is a command error and does not silently reset the project.

Component addresses persisted in manifests, state, and managed dependency metadata are written in canonical `@namespace/component` form.

## Locale Ownership

When a component declares locale resources, the install manifest records which ARB keys were added for that component. Removal uses those records to remove only keys owned by the removed component. Keys that already existed in the app ARB file, or keys also owned by another installed component, are preserved.
