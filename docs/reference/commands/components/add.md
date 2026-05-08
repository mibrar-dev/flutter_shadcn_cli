# flutter_shadcn add

> Install one or more components.

## Usage

```bash
flutter_shadcn add <component...> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<component...>` | Yes | Component names or @namespace/component addresses. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--all` | `-a` | `false` | Install every available component. |
| `--include-files <kind>` |  |  | Optional file kinds to include: readme, preview, or meta. |
| `--exclude-files <kind>` |  |  | Optional file kinds to exclude: readme, preview, or meta. |

## Examples

```bash
flutter_shadcn add button
flutter_shadcn add @shadcn/button
```

## Notes

Use namespaced addresses when multiple registries provide the same component.

## See Also

- [`flutter_shadcn list`](list.md)
- [`flutter_shadcn search`](search.md)
- [`flutter_shadcn info`](info.md)
- [`flutter_shadcn remove`](remove.md)
