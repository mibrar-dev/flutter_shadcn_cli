# Components

Components are registry-defined installable units such as buttons, dialogs, inputs, shared helpers, generated metadata, and locale resources. The registry decides which files belong to a component; the CLI installs those files into your configured install root.

## Addressing Components

Use a simple component name when it is unique:

```bash
flutter_shadcn add button
```

Use a namespace when you want a specific registry:

```bash
flutter_shadcn add @shadcn/button
```

If an unqualified name exists in more than one enabled registry, the command fails instead of guessing. Re-run with `@namespace/component`.

## Source of Truth

For v1 installs, the resolved registry manifest is the source of truth for component files, shared dependencies, dependency constraints, locale resources, manifest ownership keys, and lockfile records. If a registry does not publish a per-component manifest source, the CLI falls back to the configured component manifest or index path for that registry.

The fallback is registry-scoped. A registry that does not expose a per-component manifest source is not repeatedly probed for the same missing source during the same resolution flow.

## Installing Multiple Components

```bash
flutter_shadcn add button dialog accordion
```

Each component is resolved, dependencies are installed, shared files are copied, locale resources are merged when present, and component manifests are written.

## Locale Resources

Component locale files are component-local. A registry can publish locale resources with a component, for example `button/locales/en.json` or `button/locales/en.arb`.

Before installing locale-aware components, initialize app localization:

```bash
flutter_shadcn locale init
```

When the component is installed, the CLI merges only that component's locale keys into the configured ARB file for each locale. Existing app keys are preserved. When the component is removed, keys added by that component are removed only when no other installed component owns the same key.

## File Filters

By default, registry component files are installed according to project config and registry metadata. You can include or exclude optional file kinds per command.

```bash
flutter_shadcn add button --include-files preview
flutter_shadcn add button --include-files readme --include-files meta
flutter_shadcn add button --exclude-files preview
```

Valid file kinds:

- `readme`
- `preview`
- `meta`

Do not use `--include-files` and `--exclude-files` together.

## Installed Files

The CLI may update:

- the configured install root, usually `lib/ui/<namespace>/`
- shared files under the configured shared path
- `.shadcn/components/<component>.json`
- `.shadcn/state.json`
- `shadcn.lock`
- `lib/l10n/*.arb`, when the component declares locale resources
- `pubspec.yaml`, when the component declares managed dependencies or assets
- generated alias files, when alias generation is enabled by config

## Removing Components

```bash
flutter_shadcn remove button
```

Removal respects dependency relationships. If another installed component depends on the component you want to remove, the command fails.

To override that guard:

```bash
flutter_shadcn remove button --force
```

To remove all installed components:

```bash
flutter_shadcn remove --all
```

## Preview an Install

```bash
flutter_shadcn dry-run button
flutter_shadcn dry-run button --json
```

`dry-run` shows the planned component files, shared files, dependencies, assets, and fonts without writing them.
