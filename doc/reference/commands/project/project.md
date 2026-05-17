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

Use `project reset` to remove CLI-managed project files with a 24-hour undo window. Use `project refresh` to regenerate missing scaffolding only.

## See Also

- [`flutter_shadcn sync`](sync.md)
- [`flutter_shadcn init`](init.md)
- [`flutter_shadcn reset`](../diagnostics/reset.md)
