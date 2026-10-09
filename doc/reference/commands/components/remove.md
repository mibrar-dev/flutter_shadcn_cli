# flutter_shadcn remove

> Remove installed components and orphaned layer files.

## Aliases

- `rm`

## Usage

```bash
flutter_shadcn remove <component...> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<component...>` | No | Installed component names to remove. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--all` | `-a` | `false` | Remove every installed component. |
| `--force` | `-f` | `false` | Remove even when dependents remain. |
| `--purge-user-themes` |  | `false` | Also delete <name>_theme.dart user files. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
flutter_shadcn remove button
flutter_shadcn rm dialog
```

## See Also

- [`flutter_shadcn add`](add.md)
- [`flutter_shadcn list`](list.md)
