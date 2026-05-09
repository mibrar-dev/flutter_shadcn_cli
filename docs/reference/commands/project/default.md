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

This command does not define command-specific flags.

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
