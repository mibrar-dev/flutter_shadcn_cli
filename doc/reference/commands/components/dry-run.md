# flutter_shadcn dry-run

> Preview what would be installed.

## Usage

```bash
flutter_shadcn dry-run <component...> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<component...>` | No | Component names or @namespace/component addresses to preview. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--all` | `-a` | `false` | Preview installing every available component. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
flutter_shadcn dry-run button
flutter_shadcn dry-run --json @shadcn/card
```

## See Also

- [`flutter_shadcn add`](add.md)
- [`flutter_shadcn deps`](../diagnostics/deps.md)
