# Registry Setup

The CLI stores project registry configuration in `.shadcn/config.json` and install state in `shadcn.lock` (lockfileVersion 2).

Typical setup:

```bash
flutter_shadcn init --yes
flutter_shadcn registries
flutter_shadcn default shadcn
```

Point the CLI at a local registry checkout or a hosted URL:

```bash
flutter_shadcn --registry ../shadcn_flutter_kit/flutter_shadcn_kit/lib/registry init --yes
flutter_shadcn --registry https://example.com/registry add button
```

The registry is resolved remotely by default (GitHub raw at the CLI version's ref) and cached under `.shadcn/cache/registry` for offline re-installs.

During component install, the registry manifest (`manifests/registry.json`, schemaVersion 2) is the single source of truth: it declares each component's files, user-owned files, dependency closure and public API, plus a sha256 for every copyable file. `validate` checks the manifest; `doctor` checks the installed project against it.

References:

- [Registries](../user/registries.md)
- [Config and state](../reference/config-state.md)
- [Generated command reference](../reference/commands/index.md)
- [Developer docs](../developer/advanced-mode.md)
