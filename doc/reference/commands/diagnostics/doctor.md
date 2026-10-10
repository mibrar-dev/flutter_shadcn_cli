# flutter_shadcn doctor

> Diagnose the manifest, closure, layout and lock drift.

## Usage

```bash
flutter_shadcn doctor [--json]
```

## Arguments

This command does not define positional arguments.

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
flutter_shadcn doctor
```

## Notes

Exit codes: 0 clean, 1 drift/modified, 2 broken closure, 3 manifest invalid.

## See Also

- [`flutter_shadcn validate`](validate.md)
- [`flutter_shadcn audit`](audit.md)
- [`flutter_shadcn update`](../components/update.md)
