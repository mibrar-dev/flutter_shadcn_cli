# Troubleshooting

Start with the public diagnostics commands:

```bash
flutter_shadcn doctor
flutter_shadcn validate
flutter_shadcn audit
flutter_shadcn deps
```

For registry-specific issues, qualify the namespace when supported:

```bash
flutter_shadcn validate @shadcn
flutter_shadcn audit @shadcn
```

More help:

- [User troubleshooting](user/troubleshooting.md)
- [Diagnostics guide](guides/diagnostics.md)
- [Generated command reference](reference/commands/index.md)
- [Developer docs](developer/advanced-mode.md)
