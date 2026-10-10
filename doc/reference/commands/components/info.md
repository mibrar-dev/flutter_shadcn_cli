# flutter_shadcn info

> Show a component's or block's closure, files and api.

## Aliases

- `i`

## Usage

```bash
flutter_shadcn info <component|block> [--json]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<component|block>` | Yes | Component or block name, or @namespace/component address. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
flutter_shadcn info button
flutter_shadcn info login-01
flutter_shadcn i dialog
```

## Notes

A component reports its api and user-owned theme files; a block reports its viewport, its own files and the components it assembles.

## See Also

- [`flutter_shadcn list`](list.md)
- [`flutter_shadcn search`](search.md)
- [`flutter_shadcn add`](add.md)
