# flutter_shadcn update

> Update installed components from the registry.

## Usage

```bash
flutter_shadcn update [component...] [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `[component...]` | No | Components to update (default: all installed). |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--all` | `-a` | `false` | Update every installed component. |
| `--check` |  | `false` | Report only; exit 1 when behind or modified. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
flutter_shadcn update
flutter_shadcn update button
flutter_shadcn update --check
```

## Notes

Hash-driven: files whose bytes still match shadcn.lock are overwritten with the manifest's current content, locally modified files are reported and left, and user-owned theme files are never touched.

## See Also

- [`flutter_shadcn add`](add.md)
- [`flutter_shadcn audit`](../diagnostics/audit.md)
- [`flutter_shadcn doctor`](../diagnostics/doctor.md)
