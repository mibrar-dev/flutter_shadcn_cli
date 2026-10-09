# Troubleshooting

For scripts and CI, see the full [exit code reference](../reference/exit-codes.md). It lists every numeric process exit code, JSON error label, meaning, and recovery action.

## Component Is Ambiguous

If a component address is qualified with a namespace the CLI cannot resolve, run it unqualified or check the available registries:

```bash
flutter_shadcn registries
flutter_shadcn add button
```

## Component Cannot Be Found

Check the registry and component name:

```bash
flutter_shadcn list
flutter_shadcn search button
flutter_shadcn info button
```

If you are using `--offline`, retry without offline mode so the CLI can fetch fresh registry data.

## Registry Cannot Be Loaded

Run:

```bash
flutter_shadcn doctor
```

`doctor` prints the resolved registry root, the manifest digest, the config paths and the schema validation status.

## Schema Validation Fails

Public install, init, and add flows reject invalid registry manifests. This protects projects from installing malformed or unsafe registry data.

For local unpublished registry work, use the developer-only workflow in [../developer/local-registry-development.md](../developer/local-registry-development.md).

## File Write Rejected

The CLI rejects path traversal and symlink escapes. Keep install paths inside your Flutter project.

Examples of unsafe targets:

- `../outside-project`
- absolute paths outside the project root
- symlinks that point outside the project

## Offline Mode Fails

Offline mode needs cached registry files. Run the command once online, then retry offline:

```bash
flutter_shadcn list
flutter_shadcn --offline list
```

## Theme Command Says Registry Has No Themes

Not every registry provides theme presets. Check the registry manifest:

```bash
flutter_shadcn registries
flutter_shadcn theme list
```

If the selected registry does not declare any `themes`, use a registry that publishes presets.

## `theme apply` Refused to Overwrite the Theme

`app_theme.dart` is user-owned. If you edited it, `theme apply` reports drift (`theme_drift`, exit `80`) and leaves your file in place:

```bash
flutter_shadcn theme apply tangerine            # refused when edited
flutter_shadcn theme apply tangerine --refresh  # accept the registry theme
```

## Need Machine-Readable Output

Use `--json` on commands that support it:

```bash
flutter_shadcn list --json
flutter_shadcn info @shadcn/button --json
flutter_shadcn doctor --json
flutter_shadcn validate --json
```
