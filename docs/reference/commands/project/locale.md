# flutter_shadcn locale

> Create local Flutter localization files.

## Usage

```bash
flutter_shadcn locale <command>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<command>` | Yes | Locale command to run. Currently supported: init. |

## Flags

This command does not define command-specific flags.

## Examples

```bash
flutter_shadcn locale init
```

## Notes

`locale init` creates `l10n.yaml` and `lib/l10n/app_en.arb` so component locale resources can merge into app-local ARB files.

## See Also

- [`flutter_shadcn init`](init.md)
- [`flutter_shadcn add`](../components/add.md)
