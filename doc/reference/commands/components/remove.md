# flutter_shadcn remove

> Remove one or more installed components.

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
| `--all` | `-a` | `false` | Remove all installed components. |
| `--force` | `-f` | `false` | Skip confirmation prompts. |

## Examples

```bash
flutter_shadcn remove button
flutter_shadcn rm dialog
```

## See Also

- [`flutter_shadcn add`](add.md)
- [`flutter_shadcn list`](list.md)
