# Diagnostics

Use diagnostics commands before editing generated files or registry metadata by hand.

```bash
flutter_shadcn doctor
flutter_shadcn validate
flutter_shadcn audit
flutter_shadcn update --check
```

Common checks:

- `doctor` reports the resolved registry, the install layout, closure gaps and lock drift.
- `validate` checks the registry manifest against the v2 schema and referenced files.
- `audit` compares installed files with the hashes recorded in `shadcn.lock`.
- `update --check` reports whether anything is behind or locally modified without writing.

References:

- [Troubleshooting](../troubleshooting.md)
- [User troubleshooting](../user/troubleshooting.md)
- [Generated command reference](../reference/commands/index.md)
- [Developer docs](../developer/advanced-mode.md)
