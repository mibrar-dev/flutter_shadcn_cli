# Getting Started

Initialize a Flutter project, then add components from the default registry.

```bash
flutter_shadcn init --yes
flutter_shadcn add button
```

Use namespaced component addresses when you need a specific registry or when a component may exist in more than one enabled registry.

```bash
flutter_shadcn add @shadcn/button
```

For locale-aware components, create the Flutter localization files before installing those components:

```bash
flutter_shadcn locale init
flutter_shadcn add button
```

Only installed components contribute locale keys. The CLI merges component-local JSON or ARB resources into the app ARB files during `add`.

Learn more:

- [Installation](installation.md)
- [User getting started](user/getting-started.md)
- [Component workflow](guides/component-workflow.md)
- [Generated command reference](reference/commands/index.md)
- [Developer docs](developer/advanced-mode.md)
