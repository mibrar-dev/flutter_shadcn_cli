# flutter_shadcn

`flutter_shadcn` installs Flutter shadcn components from one or more registries into an existing Flutter project. The CLI keeps registry configuration in `.shadcn/config.json`, install state in `.shadcn/state.json`, per-component install manifests in `.shadcn/components/`, and v1 source records in `shadcn.lock`.

## Install

```bash
dart pub global activate flutter_shadcn_cli
flutter_shadcn version
```

Make sure the Dart pub cache bin directory is on your shell path before running `flutter_shadcn`.

## Quick Start

Run commands from your Flutter project root:

```bash
flutter_shadcn init --yes
flutter_shadcn add button
```

Use a namespaced address when you want a component from a specific registry:

```bash
flutter_shadcn add @shadcn/button
```

If an unqualified component name exists in more than one enabled registry, `add` fails and asks for `@namespace/component`.

## Current v1 Behavior

- `init [namespace]` resolves the registry directory entry, writes project config/state, and runs inline `init.actions` from `registries.json`.
- `init --yes` installs the required bootstrap surface only. Optional fonts, icons, and assets are installed later with `flutter_shadcn assets`.
- `add` resolves components from enabled registries, installs component files, shared files, dependencies, per-component locale resources, and component manifests.
- Component locale resources are per component. Installing `button` merges only the `button` locale resource keys into the app ARB files; installing another component later merges only that component's keys.
- Registry manifests are the source of truth. The CLI prefers the resolved registry manifest path for a component and falls back through configured manifest/index paths only when the registry does not publish a per-component manifest source.
- Legacy `.shadcn/config.json` and `.shadcn/state.json` files are normalized on load. Invalid JSON fails the command instead of silently resetting project state.

## Common Commands

```bash
flutter_shadcn registries
flutter_shadcn list
flutter_shadcn search button
flutter_shadcn info @shadcn/button
flutter_shadcn dry-run button
flutter_shadcn remove button
flutter_shadcn locale init
flutter_shadcn assets --list
flutter_shadcn doctor
```

## Documentation

- Start here: [docs/index.md](docs/index.md)
- User getting started: [docs/user/getting-started.md](docs/user/getting-started.md)
- Testing and usage guide: [docs/testing-guide.md](docs/testing-guide.md)
- Commands: [docs/user/commands.md](docs/user/commands.md)
- Components: [docs/user/components.md](docs/user/components.md)
- Registries: [docs/user/registries.md](docs/user/registries.md)
- Command reference: [docs/reference/commands/index.md](docs/reference/commands/index.md)
- Registry directory reference: [docs/reference/registries-json.md](docs/reference/registries-json.md)
- Inline init actions: [docs/reference/inline-init-actions.md](docs/reference/inline-init-actions.md)
- Developer docs: [docs/developer/local-registry-development.md](docs/developer/local-registry-development.md)
