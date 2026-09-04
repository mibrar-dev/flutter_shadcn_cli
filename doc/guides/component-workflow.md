# Component Workflow

Use `init` once per project, create localization files when needed, then install components with `add`.

```bash
flutter_shadcn init --yes
flutter_shadcn locale init
flutter_shadcn add button
flutter_shadcn add @shadcn/button
```

The CLI installs only what each selected component declares. A component can add files, shared dependencies, pubspec entries, and component-local locale keys. Those writes are recorded in `.shadcn/components/<component>.json` and `shadcn.lock` so later `remove`, `audit`, and `doctor` commands can reason from installed state.

Useful follow-up commands:

- `flutter_shadcn list` to browse components.
- `flutter_shadcn search button` to find matching components.
- `flutter_shadcn info @shadcn/button` to inspect one component.
- `flutter_shadcn dry-run button` to preview writes.
- `flutter_shadcn remove button` to uninstall a component.
- `flutter_shadcn assets --list` to inspect optional registry asset actions.

References:

- [User commands](../user/commands.md)
- [Components](../user/components.md)
- [Generated command reference](../reference/commands/index.md)
- [Developer docs](../developer/advanced-mode.md)
