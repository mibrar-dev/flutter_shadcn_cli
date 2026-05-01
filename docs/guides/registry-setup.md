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

References:

- [Registries](../user/registries.md)
- [Config and state](../reference/config-state.md)
- [registries.json](../reference/registries-json.md)
- [Generated command reference](../reference/commands/index.md)
- [Developer docs](../developer/advanced-mode.md)
