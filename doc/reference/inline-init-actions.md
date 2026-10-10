# Inline Init Actions (retired)

Inline init actions (`registries[].init.actions` in a `registries.json` directory) belonged to the v1 registry format. The v2 CLI does not execute them.

`flutter_shadcn init` now installs the always-on layer core directly from the registry manifest (`manifests/registry.json`, schemaVersion 2):

- every `foundation` unit
- every `theme` unit
- the generated `<installRoot>/theme/app_theme.dart`

There is no separate asset, locale or inline-action step. A registry declares what a component needs through the manifest's `deps` and `packages` blocks, and `add` installs that closure.
