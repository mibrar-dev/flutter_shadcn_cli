# Registry Setup

The CLI stores project registry configuration in `.shadcn/config.json` and install state in `.shadcn/state.json`.

Typical setup:

```bash
flutter_shadcn init shadcn --yes
flutter_shadcn registries
flutter_shadcn default shadcn
```

Use namespaced addresses for explicit registry selection:

```bash
flutter_shadcn add @shadcn/button
flutter_shadcn list @shadcn
```

Registry setup is driven by the registry directory. Each entry defines the namespace, base URL or local path, install root, manifest paths, trust metadata, capabilities, and inline init actions.

During component install, the registry manifest for that namespace is the source of truth. Per-component manifest sources are preferred when a registry publishes them. Registries that do not publish those sources fall back to their configured `components.json` or index metadata without changing behavior for single-registry projects.

Optional assets are separate from required init:

```bash
flutter_shadcn assets --typography
flutter_shadcn assets --icons
```

References:

- [Registries](../user/registries.md)
- [Config and state](../reference/config-state.md)
- [registries.json](../reference/registries-json.md)
- [Generated command reference](../reference/commands/index.md)
- [Developer docs](../developer/advanced-mode.md)
