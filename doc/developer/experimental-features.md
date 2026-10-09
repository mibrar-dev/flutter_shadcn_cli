# Experimental Features

Experimental features must be documented as advanced workflows until they are stable enough for the default user help.

Current advanced-only surfaces:

- `flutter_shadcn --advanced docs --generate`

Registry source overrides are public:

- `--registry <path|url>`

Theme preset inputs are public (`theme list` / `theme apply <preset>`); the v1 widget-theme artifact flows (`--apply-file` / `--apply-url`) were retired in the v2 rewrite.

When promoting an experimental feature, update parser gating, command metadata, generated reference docs, and these developer docs in the same change.

References:

- [Advanced mode](advanced-mode.md)
- [Generated command reference](../reference/commands/index.md)
