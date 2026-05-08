# Getting Started

`flutter_shadcn` installs Flutter UI components from one or more registries into your project. It keeps project configuration in `.shadcn/config.json`, install state in `.shadcn/state.json`, component install manifests in `.shadcn/components/`, and v1 registry source records in `shadcn.lock`.

## Install

```bash
dart pub global activate flutter_shadcn_cli
```

Make sure the Dart pub cache bin directory is on your shell path.

## Initialize a Project

Run this from your Flutter project root:

```bash
flutter_shadcn init --yes
```

This selects the default registry namespace, creates the `.shadcn` folder, and runs the registry's inline bootstrap actions. Bootstrap actions usually create shared UI files, add required dependencies, and copy font or theme assets.

To initialize a specific registry namespace:

```bash
flutter_shadcn init shadcn --yes
```

Non-interactive `init --yes` installs only the required bootstrap surface for the selected registry. Optional fonts, icons, and asset packs are installed explicitly with `flutter_shadcn assets`.

## Initialize Localization

Locale-aware components require Flutter localization files in the app before their locale resources can be merged:

```bash
flutter_shadcn locale init
```

This creates `l10n.yaml`, `lib/l10n/`, and `lib/l10n/app_en.arb` when they do not already exist. Component installs then merge only the locale resources published by the installed component into the app ARB files.

## Add Your First Component

Install a component from the default registry:

```bash
flutter_shadcn add button
```

Install a component from a specific registry:

```bash
flutter_shadcn add @shadcn/button
```

Use the namespaced form whenever two enabled registries provide the same component name.

During install, the CLI reads the resolved registry manifest source for the component, installs declared files and dependencies, merges component-local locale resources when present, writes `.shadcn/components/<component>.json`, and updates `shadcn.lock`.

## Find Components

```bash
flutter_shadcn list
flutter_shadcn search button
flutter_shadcn info @shadcn/button
```

`list` shows available components, `search` filters by text, and `info` shows details for one component.

## Common Workflow

```bash
flutter_shadcn init --yes
flutter_shadcn list
flutter_shadcn add button
flutter_shadcn doctor
```

Use `doctor` after setup or when registry resolution feels wrong.

## More Docs

- Command guide: [commands.md](commands.md)
- Components: [components.md](components.md)
- Registries: [registries.md](registries.md)
- Troubleshooting: [troubleshooting.md](troubleshooting.md)
