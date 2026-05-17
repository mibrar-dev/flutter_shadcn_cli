# flutter_shadcn platform

> Configure platform target paths.

## Usage

```bash
flutter_shadcn platform [flags]
```

## Arguments

This command does not define positional arguments.

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--set <platform.section=path>` |  |  | Set a platform target path. |
| `--reset <platform.section>` |  |  | Remove a platform target override. |
| `--list` |  | `false` | List configured platform targets. |

## Examples

```bash
flutter_shadcn platform --list
flutter_shadcn platform --set ios.runner=ios/Runner
```

## See Also

- [`flutter_shadcn init`](init.md)
- [`flutter_shadcn sync`](sync.md)
