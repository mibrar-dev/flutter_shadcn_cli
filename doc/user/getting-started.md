# Getting Started

`flutter_shadcn` installs Flutter UI components from one or more registries into your project. It keeps project configuration in `.shadcn/config.json`, install state in `.shadcn/state.json`, and component manifests in `.shadcn/components/`.

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

- Complete A-Z guide: [complete-guide.md](complete-guide.md)
- Command guide: [commands.md](commands.md)
- Components: [components.md](components.md)
- Registries: [registries.md](registries.md)
- Troubleshooting: [troubleshooting.md](troubleshooting.md)
