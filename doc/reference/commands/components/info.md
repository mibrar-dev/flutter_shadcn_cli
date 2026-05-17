# flutter_shadcn info

> Show component details.

## Aliases

- `i`

## Usage

```bash
flutter_shadcn info <component> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<component>` | Yes | Component name or @namespace/component address. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--refresh` |  | `false` | Refresh cached registry data before loading details. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
flutter_shadcn info button
flutter_shadcn i @shadcn/dialog
```

## See Also

- [`flutter_shadcn list`](list.md)
- [`flutter_shadcn search`](search.md)
- [`flutter_shadcn add`](add.md)
