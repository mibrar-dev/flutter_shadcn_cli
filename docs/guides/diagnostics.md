# Diagnostics

Use diagnostics commands before editing generated files or registry metadata by hand.

```bash
flutter_shadcn doctor
flutter_shadcn validate
flutter_shadcn audit
flutter_shadcn deps
```

Common checks:

- `doctor` reports project and registry configuration.
- `validate` checks registry schema and referenced files.
- `audit` compares installed component manifests with registry metadata.
- `deps` compares registry dependencies with `pubspec.yaml`.

References:

- [Troubleshooting](../troubleshooting.md)
- [User troubleshooting](../user/troubleshooting.md)
- [Generated command reference](../reference/commands/index.md)
- [Developer docs](../developer/advanced-mode.md)
