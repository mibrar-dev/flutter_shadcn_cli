# flutter_shadcn search

> Search components and blocks by name, description or tag.

## Usage

```bash
flutter_shadcn search <query> [--category <name>] [--json]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<query>` | Yes | Search text. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--category <name>` |  | `false` | Only entries of that category. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
flutter_shadcn search button
flutter_shadcn search login --category Authentication
```

## Notes

Both kinds are searched at once, because `add <id>` resolves both. Each result carries its `kind`, `category` and, for a block, its `viewport`.

## See Also

- [`flutter_shadcn list`](list.md)
- [`flutter_shadcn info`](info.md)
