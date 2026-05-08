# flutter_shadcn init

> Initialize shadcn_flutter in the current project.

## Usage

```bash
flutter_shadcn init [namespace] [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `[namespace]` | No | Registry namespace to initialize from. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--yes` | `-y` | `false` | Run non-interactively and use defaults. |

## Examples

```bash
flutter_shadcn init
flutter_shadcn init shadcn --yes
```

## Notes

`init` runs inline registry bootstrap actions from `registries.json`. Non-interactive `init --yes` installs the required project surface only; optional fonts, icons, and asset packs are installed with `assets`.

## See Also

- [`flutter_shadcn registries`](registries.md)
- [`flutter_shadcn default`](default.md)
- [`flutter_shadcn sync`](sync.md)
