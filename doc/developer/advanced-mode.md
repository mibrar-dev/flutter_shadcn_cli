# Advanced Mode

`--advanced` is the opt-in switch for developer CLI surfaces.

```bash
flutter_shadcn --advanced --help
flutter_shadcn --advanced docs --generate
```

Advanced mode is position-flexible, so the flag may appear before or after the command.

## Advanced Commands

These commands require `--advanced`:

- `docs`

## Registry Overrides

Pointing the CLI at a registry is a public option, not an advanced one:

```bash
flutter_shadcn --registry /absolute/path/to/registry list
flutter_shadcn --registry https://example.com/registry add button
```

Use `--registry <path|url>` for local registry development, schema testing, and controlled maintenance workflows.

## Themes

Applying a named theme preset is public:

```bash
flutter_shadcn theme list
flutter_shadcn theme apply modern-minimal
```

Each registry owns its theme format. The CLI consumes the preset JSON (`themes/<id>.json`, schemaVersion 2) and writes a values-only `app_theme.dart`. Widget theme artifacts and the old `--apply-file`/`--apply-url` inputs are not part of the v2 surface.

References:

- [Experimental features](experimental-features.md)
- [Generated command reference](../reference/commands/index.md)
