# Registries

A registry publishes a manifest (`manifests/registry.json`, schemaVersion 2) plus the component, primitive, foundation and theme files it describes. The CLI resolves the registry remotely by default and can be pointed at a local checkout or an `http(s)` URL.

## Registry Source

Resolution order:

1. `--registry <path|url>` on the command line.
2. `SHADCN_REGISTRY_ROOT` / `SHADCN_REGISTRY_URL` environment variables.
3. `registryPath` / `registryUrl` in `.shadcn/config.json` (written by `init`).
4. The default remote registry (GitHub raw at the CLI version's ref).

```bash
flutter_shadcn --registry ../shadcn_flutter_kit/flutter_shadcn_kit/lib/registry add button
flutter_shadcn --registry https://example.com/registry validate
```

A remote registry is cached under `.shadcn/cache/registry`; `--offline` reads the cache and never touches the network.

## List Registries

```bash
flutter_shadcn registries
flutter_shadcn registries --json
```

## Set the Default Registry

```bash
flutter_shadcn default shadcn
flutter_shadcn default shadcn --local
flutter_shadcn default shadcn --remote
```

To see the current default:

```bash
flutter_shadcn default
```

## Component Addresses

Component commands accept an optional `@namespace/` prefix; the CLI strips it and resolves the component from the active registry.

```bash
flutter_shadcn add button
flutter_shadcn info button
flutter_shadcn search button
```

## Offline Mode

```bash
flutter_shadcn --offline list
```

Offline mode disables network calls and uses the cache. Use it only after the registry has been fetched once.

## Manifest Resolution

The manifest is the single source of truth for a component:

- `components/<id>` declares the component's files, user-owned files, deps and public API.
- `foundation`, `theme` and `primitives` declare the layer units.
- `fileHashes` records a sha256 for every copyable file.

`validate` checks the manifest against the v2 rules; `doctor` checks the installed project against the manifest and `shadcn.lock`.

## Init

`flutter_shadcn init [--dir <path>] [--theme <id>] [--yes]` copies the always-on foundation + theme core, writes `.shadcn/config.json` and `shadcn.lock`, and generates `<installRoot>/theme/app_theme.dart`. It never installs a component.
