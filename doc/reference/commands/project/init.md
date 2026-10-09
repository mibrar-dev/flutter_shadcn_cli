# flutter_shadcn init

> Install the layer core and generate the app theme.

## Usage

```bash
flutter_shadcn init [flags]
```

## Arguments

This command does not define positional arguments.

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--dir <path>` |  |  | Install root (default: lib/ui/shadcn). |
| `--theme <id>` |  |  | Theme preset id (default: vercel). |
| `--yes` | `-y` | `false` | Non-interactive; use the default preset. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
flutter_shadcn init
flutter_shadcn init --theme vercel --yes
```

## Notes

Copies every foundation and theme unit (no component), writes .shadcn/config.json and shadcn.lock v2, and generates <installRoot>/theme/app_theme.dart from the chosen preset.

## See Also

- [`flutter_shadcn registries`](registries.md)
- [`flutter_shadcn default`](default.md)
- [`flutter_shadcn theme`](theme.md)
- [`flutter_shadcn add`](../components/add.md)
