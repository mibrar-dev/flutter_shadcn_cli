# flutter_shadcn add

> Install one or more components or blocks and their closure.

## Usage

```bash
flutter_shadcn add <component|block...> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<component|block...>` | Yes | Component or block names, or @namespace/component addresses. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--all` | `-a` | `false` | Install every available component. |
| `--blocks` |  | `false` | With --all, install every block too. |
| `--dry-run` |  | `false` | Print the plan without writing anything. |
| `--force` | `-f` | `false` | Overwrite locally modified registry files. |
| `--include-preview` |  | `false` | Also copy each component preview.dart. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
flutter_shadcn add button
flutter_shadcn add login-01
flutter_shadcn add input select tabs
flutter_shadcn add --all --blocks
```

## Notes

Installs the transitive closure: requested components and blocks, their components/primitives deps, and the always-on foundation + theme core. A block lands in blocks/<id>/ together with the components it uses. User-owned <name>_theme.dart files are never overwritten.

## See Also

- [`flutter_shadcn remove`](remove.md)
- [`flutter_shadcn update`](update.md)
- [`flutter_shadcn list`](list.md)
- [`flutter_shadcn info`](info.md)
- [`flutter_shadcn dry-run`](dry-run.md)
