# Advanced Mode

`--advanced` is the opt-in switch for developer and experimental CLI surfaces.

```bash
flutter_shadcn --advanced --help
flutter_shadcn --advanced docs --generate
flutter_shadcn docs --advanced --help
```

Advanced mode is position-flexible, so the flag may appear before or after the command.

## Advanced Commands

These commands require `--advanced`:

- `docs`
- `install-skill`

## Developer Flags

These global flags require `--advanced`:

- `--registry-path <path>`
- `--registry-url <url>`
- `--registries-path <path>`
- `--skip-integrity`

Use them for local registry development, schema testing, and controlled maintenance workflows. Public project setup should use configured registries and normal commands.

## Theme Imports

Applying a named theme preset remains public:

```bash
flutter_shadcn theme --apply modern-minimal
```

Theme JSON file and URL imports are advanced-only:

```bash
flutter_shadcn --advanced theme --apply-file theme.json
flutter_shadcn --advanced theme --apply-url https://example.com/theme.json
flutter_shadcn --advanced theme widget button --apply-file button-theme.json
flutter_shadcn --advanced theme widget button --apply-url https://example.com/button-theme.json
```

References:

- [Experimental features](experimental-features.md)
- [Advanced workflows](../guides/advanced-workflows.md)
- [Generated command reference](../reference/commands/index.md)
