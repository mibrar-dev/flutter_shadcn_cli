# `registries.json` (legacy registry directory)

`registries.json` was the v1 registry directory: it told the CLI where a registry's `components.json`, `index.json` and theme catalog lived, and which inline init actions ran during `init`.

The v2 CLI resolves a single registry manifest (`manifests/registry.json`, schemaVersion 2) per source instead. The manifest declares the components, layer units, theme presets and file hashes directly; there is no `components.json`/`index.json` fallback and no inline init actions.

## Registry Source

The registry source is resolved from, in order:

1. `--registry <path|url>`
2. `SHADCN_REGISTRY_ROOT` / `SHADCN_REGISTRY_URL`
3. `registryPath` / `registryUrl` in `.shadcn/config.json`
4. The default remote registry

`flutter_shadcn registries` still reads an optional registry directory (when `registriesPath` is configured) to list discoverable registries, but installs always use the v2 manifest. See [Registries](../user/registries.md) and [Registry setup](../guides/registry-setup.md).
