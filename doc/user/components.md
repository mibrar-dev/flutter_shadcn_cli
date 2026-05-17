# Components

Components are registry-defined installable units such as buttons, dialogs, inputs, themes, shared helpers, and generated metadata. The registry decides which files belong to a component; the CLI installs those files into your configured install root.

## Addressing Components

Use a simple component name when it is unique:

```bash
flutter_shadcn add button
```

Use a namespace when you want a specific registry:

```bash
flutter_shadcn add @shadcn/button
```

## Installing Multiple Components

```bash
flutter_shadcn add button dialog accordion
```

Each component is resolved, dependencies are installed, shared files are copied, and component manifests are written.

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
