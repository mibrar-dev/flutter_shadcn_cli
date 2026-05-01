# flutter_shadcn install-skill

> Install AI skills for local model workflows.

This command requires `--advanced`.

## Usage

```bash
flutter_shadcn --advanced install-skill [flags]
```

## Arguments

This command does not define positional arguments.

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--skill <id>` | `-s` |  | Skill id to install. |
| `--model <name>` | `-m` |  | Model name to install for. |
| `--skills-url <url-or-path>` |  |  | Override the skills base URL or local path. |
| `--symlink` |  | `false` | Symlink a shared skill to the model. |
| `--list` |  | `false` | List installed skills. |
| `--available` | `-a` | `false` | List available skills from the registry. |
| `--interactive` | `-i` | `false` | Run interactive multi-skill installation. |
| `--uninstall <id>` |  |  | Uninstall a skill. |
| `--uninstall-interactive` |  | `false` | Run interactive removal. |

## Examples

```bash
flutter_shadcn --advanced install-skill --available
flutter_shadcn --advanced install-skill --skill design --model gpt-4
```

## Notes

This command requires --advanced.

## See Also

- [`flutter_shadcn docs`](docs.md)
