# flutter_shadcn theme

> Manage registry theme presets.

## Usage

```bash
flutter_shadcn theme [id] [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `[id]` | No | Theme preset id to apply. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--list` |  | `false` | List theme presets. |
| `--refresh` |  | `false` | Refresh cached theme data. |
| `--apply <id>` | `-a` |  | Apply a registry theme preset. |
| `--apply-file <path>` |  |  | Apply a theme from a local JSON file. Requires `--advanced`. |
| `--apply-url <url>` |  |  | Apply a theme from a JSON URL. Requires `--advanced`. |

## Examples

```bash
flutter_shadcn theme --list
flutter_shadcn theme --apply neutral
flutter_shadcn --advanced theme --apply-file theme.json
```

## Notes

File and URL theme imports require --advanced. The theme widget subcommand supports widget-level list, list-targets, reset, apply-file, and apply-url workflows.

## See Also

- [`flutter_shadcn assets`](assets.md)
- [`flutter_shadcn init`](init.md)
