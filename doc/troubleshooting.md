# Troubleshooting

Start with the public diagnostics commands:

```bash
flutter_shadcn doctor
flutter_shadcn validate
flutter_shadcn audit
flutter_shadcn update --check
```

For registry-specific issues, point the CLI at a registry explicitly:

```bash
flutter_shadcn --registry <path|url> validate
flutter_shadcn --registry <path|url> doctor
```

More help:

- [User troubleshooting](user/troubleshooting.md)
- [Diagnostics guide](guides/diagnostics.md)
- [Generated command reference](reference/commands/index.md)
- [Developer docs](developer/advanced-mode.md)
