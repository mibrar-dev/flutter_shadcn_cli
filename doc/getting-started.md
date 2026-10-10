# Getting Started

Initialize a Flutter project, then add components from the registry.

```bash
flutter_shadcn init --yes
flutter_shadcn add button
```

An `@namespace/` prefix is accepted on component addresses and stripped:

```bash
flutter_shadcn add @shadcn/button
```

Keep the install up to date and inspect it:

```bash
flutter_shadcn update --check
flutter_shadcn doctor
flutter_shadcn theme list
```

Learn more:

- [Installation](installation.md)
- [User getting started](user/getting-started.md)
- [Component workflow](guides/component-workflow.md)
- [Generated command reference](reference/commands/index.md)
- [Developer docs](developer/advanced-mode.md)
