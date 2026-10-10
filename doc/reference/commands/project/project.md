# flutter_shadcn project

> Project repair and cleanup commands.

## Usage

```bash
flutter_shadcn project <reset|refresh> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<reset|refresh>` | Yes | Project-scoped maintenance command to run. |

## Flags

This command does not define command-specific flags.

## Examples

```bash
flutter_shadcn project reset
flutter_shadcn project reset --undo
flutter_shadcn project refresh
```

## Notes

`project reset` removes CLI-managed files with a 24-hour undo window. `project refresh` re-applies the installed closure and locked theme.

## See Also

- [`flutter_shadcn sync`](sync.md)
- [`flutter_shadcn init`](init.md)
- [`flutter_shadcn reset`](../diagnostics/reset.md)
