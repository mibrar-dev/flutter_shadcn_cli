# Component Workflow

Use `init` once per project, then install components with `add`.

```bash
flutter_shadcn init --yes
flutter_shadcn add button
flutter_shadcn add button dialog input select calendar
```

The CLI installs only what each selected component declares: the component files, its transitive layer closure (primitives, foundation, theme) and any pub packages those need. Those writes are recorded in `shadcn.lock` so later `remove`, `update`, `audit` and `doctor` commands can reason from installed state.

Useful follow-up commands:

- `flutter_shadcn list` to browse components.
- `flutter_shadcn search button` to find matching components.
- `flutter_shadcn info button` to inspect one component's closure and API.
- `flutter_shadcn dry-run button` to preview writes.
- `flutter_shadcn update --check` to see whether the registry moved on.
- `flutter_shadcn remove button` to uninstall a component.

References:

- [User commands](../user/commands.md)
- [Components](../user/components.md)
- [Generated command reference](../reference/commands/index.md)
- [Developer docs](../developer/advanced-mode.md)
