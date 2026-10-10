# flutter_shadcn list

> List available components or blocks, by category.

## Aliases

- `ls`

## Usage

```bash
flutter_shadcn list [--blocks] [--category <name>] [--json]
```

## Arguments

This command does not define positional arguments.

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--blocks` |  | `false` | List the blocks layer instead of components. |
| `--category <name>` |  | `false` | Only entries of that category. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
flutter_shadcn list
flutter_shadcn list --blocks
flutter_shadcn list --category "Forms & Inputs"
flutter_shadcn ls --json
```

## Notes

Human output groups entries by the category each meta.json declares; the JSON envelope keeps both `components` and `blocks` so a consumer never has to probe for a key.

## See Also

- [`flutter_shadcn search`](search.md)
- [`flutter_shadcn info`](info.md)
- [`flutter_shadcn add`](add.md)
