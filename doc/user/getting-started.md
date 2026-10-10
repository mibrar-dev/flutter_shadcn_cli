# Getting Started

`flutter_shadcn` installs Flutter UI components from a registry into your project. It keeps project configuration in `.shadcn/config.json` and install state in `shadcn.lock` (lockfileVersion 2).

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

This copies the always-on foundation + theme layers, writes `.shadcn/config.json` and `shadcn.lock`, and generates `<installRoot>/theme/app_theme.dart` from a preset (`vercel` by default). It does not install any component.

Choose a different preset or install root:

```bash
flutter_shadcn init --theme claude --yes
flutter_shadcn init --dir lib/shadcn --yes
```

## Add Your First Component

```bash
flutter_shadcn add button
```

The CLI resolves the component's closure, copies the files into `lib/ui/shadcn/`, adds any missing pub packages to `pubspec.yaml`, and updates `shadcn.lock`.

## Find Components

```bash
flutter_shadcn list
flutter_shadcn search button
flutter_shadcn info button
```

`list` shows available components, `search` filters by text, and `info` shows a component's closure, files and public API.

## Update and Remove

```bash
flutter_shadcn update --check
flutter_shadcn update button
flutter_shadcn remove button
```

## Themes

```bash
flutter_shadcn theme list
flutter_shadcn theme apply tangerine
```

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
