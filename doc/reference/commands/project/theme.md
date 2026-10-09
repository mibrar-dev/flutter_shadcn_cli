# flutter_shadcn theme

> List and apply registry theme presets.

## Usage

```bash
flutter_shadcn theme <list|apply <preset>> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<list|apply>` | No | Theme action to run. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--refresh` |  | `false` | Overwrite app_theme.dart even when edited. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
flutter_shadcn theme list
flutter_shadcn theme apply vercel
```

## Notes

app_theme.dart is user-owned: without --refresh a locally modified file is reported as drift and left untouched.

## See Also

- [`flutter_shadcn init`](init.md)
- [`flutter_shadcn add`](../components/add.md)
