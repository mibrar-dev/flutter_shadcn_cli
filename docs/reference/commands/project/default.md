# flutter_shadcn default

> Set or show the default registry namespace and source mode.

## Usage

```bash
flutter_shadcn default [namespace] [--local | --remote]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `[namespace]` | No | Registry namespace to set as default. |

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--local` | `false` | Persist local development paths for the selected namespace. |
| `--remote` | `false` | Switch the selected namespace back to the published remote registry. |

## Examples

```bash
flutter_shadcn default
flutter_shadcn default shadcn
flutter_shadcn --advanced default shadcn --local
flutter_shadcn --advanced default shadcn --remote
```

## See Also

- [`flutter_shadcn registries`](registries.md)
- [`flutter_shadcn init`](init.md)
