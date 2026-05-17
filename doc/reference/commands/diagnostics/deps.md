# flutter_shadcn deps

> Compare registry dependencies against pubspec.yaml.

## Usage

```bash
flutter_shadcn deps [component...] [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `[component...]` | No | Optional component names to check. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--all` | `-a` | `false` | Compare dependencies for all registry components. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
flutter_shadcn deps button
flutter_shadcn deps --all
```

## See Also

- [`flutter_shadcn audit`](audit.md)
- [`flutter_shadcn dry-run`](../components/dry-run.md)
