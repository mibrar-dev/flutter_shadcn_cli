# Experimental Features

Experimental features must be documented as advanced workflows until they are stable enough for the default user help.

Current advanced-only surfaces:

- `flutter_shadcn --advanced docs --generate`
- `flutter_shadcn --advanced install-skill`
- `flutter_shadcn --advanced theme --apply-file <path>`
- `flutter_shadcn --advanced theme --apply-url <url>`
- `flutter_shadcn --advanced theme widget <target> --apply-file <path>`
- `flutter_shadcn --advanced theme widget <target> --apply-url <url>`

Developer-only registry overrides also require `--advanced`:

- `--registry-path <path>`
- `--registry-url <url>`
- `--registries-path <path>`
- `--skip-integrity`

When promoting an experimental feature, update parser gating, command metadata, generated reference docs, and these developer docs in the same change.

References:

- [Advanced mode](advanced-mode.md)
- [Advanced workflows](../guides/advanced-workflows.md)
- [Generated command reference](../reference/commands/index.md)
