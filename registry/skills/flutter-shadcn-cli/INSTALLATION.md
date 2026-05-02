# Install The Flutter shadcn CLI Skill

This skill ships inside the `flutter_shadcn_cli` pub package under `registry/skills`.

```bash
dart pub global activate flutter_shadcn_cli
flutter_shadcn --advanced install-skill --available
flutter_shadcn --advanced install-skill --skill flutter-shadcn-cli --model .codex
```

Install the UI skill the same way:

```bash
flutter_shadcn --advanced install-skill --skill flutter-shadcn-ui --model .codex
```

For local development from this repo:

```bash
dart run bin/flutter_shadcn.dart --advanced install-skill --available
dart run bin/flutter_shadcn.dart --advanced install-skill --skill flutter-shadcn-cli --model .codex
```

Verify:

```bash
flutter_shadcn --advanced install-skill --list
```
