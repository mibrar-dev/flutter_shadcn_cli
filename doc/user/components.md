# Components

Components are registry-defined installable units such as buttons, dialogs, inputs and calendars. The registry manifest decides which files belong to a component; the CLI installs those files into your configured install root.

## Addressing Components

Use the component id from `list`/`search`:

```bash
flutter_shadcn add button
```

An `@namespace/` prefix is accepted and stripped, so `@shadcn/button` installs `button`.

## Source of Truth

The registry manifest (`manifests/registry.json`, schemaVersion 2) is the single source of truth. Each `components/<id>` entry declares:

- `files`: the registry-owned files copied verbatim
- `userOwned`: `<name>_theme.dart` files the CLI writes once and never overwrites
- `deps`: the component/primitive/foundation/theme closure
- `api`: the public symbols, used for the single-owner preflight

## Installing Multiple Components

```bash
flutter_shadcn add button dialog input select calendar
```

The CLI resolves the transitive closure, refuses an install that would define the same public symbol twice, copies the files, adds missing pub packages to `pubspec.yaml`, runs `flutter pub get`, and updates `shadcn.lock`.

## Installed Files

The CLI writes:

- the depth-preserving install root (default `lib/ui/shadcn/`): `foundation/`, `theme/`, `primitives/`, `components/<id>/`
- `<installRoot>/theme/app_theme.dart` (generated from a theme preset)
- `.shadcn/config.json` and `shadcn.lock`
- `pubspec.yaml`, when the closure declares managed packages

## User-Owned Theme Files

`<name>_theme.dart` files are yours. `add`, `update` and `remove` never overwrite or delete them; `remove --purge-user-themes` is the only way to delete them.

## Removing Components

```bash
flutter_shadcn remove button
```

Removal respects dependency relationships: if another installed component still depends on the one you want to remove, the command refuses.

To override that guard:

```bash
flutter_shadcn remove button --force
```

To remove all installed components:

```bash
flutter_shadcn remove --all
```

## Updating Components

```bash
flutter_shadcn update --check
flutter_shadcn update button
```

`update` overwrites files whose bytes still match `shadcn.lock`, installs files the manifest has added since the install, and reports locally modified files without touching them.

## Preview an Install

```bash
flutter_shadcn dry-run button
flutter_shadcn dry-run button --json
```

`dry-run` shows the planned component files, layer units, dependencies and missing packages without writing them.
