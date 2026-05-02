# flutter_shadcn Commands For Agents

Do not invent flags. Prefer `--json` when parsing output.

## Public Commands

```bash
flutter_shadcn init [namespace] --yes
flutter_shadcn add @shadcn/button @shadcn/card
flutter_shadcn dry-run @shadcn/dialog --json
flutter_shadcn remove @shadcn/dialog
flutter_shadcn list @shadcn --json
flutter_shadcn search @shadcn button --json
flutter_shadcn info @shadcn/button --json
flutter_shadcn sync
flutter_shadcn doctor --json
flutter_shadcn validate --json
flutter_shadcn audit --json
flutter_shadcn deps --json
flutter_shadcn registries --json
flutter_shadcn default
flutter_shadcn default shadcn
flutter_shadcn assets --icons
flutter_shadcn assets --typography
flutter_shadcn theme --list
flutter_shadcn theme --apply modern-minimal
flutter_shadcn theme widget --list
flutter_shadcn platform --list
flutter_shadcn version --check
flutter_shadcn feedback --type bug --title "..." --body "..."
```

## Advanced Commands And Flags

Advanced surfaces require `--advanced`.

```bash
flutter_shadcn --advanced docs --generate
flutter_shadcn --advanced install-skill --available
flutter_shadcn --advanced install-skill --skill flutter-shadcn-ui --model .codex
flutter_shadcn --advanced --registry-path ../registry validate
flutter_shadcn --advanced --registries-path ./registries.json registries --json
flutter_shadcn --advanced --skip-integrity --registry-path ../registry add @shadcn/button
```

Use `--skip-integrity` only for unpublished local registry authoring. Never put it in production docs.

## Namespace Rules

- Prefer `@namespace/component`.
- Use `flutter_shadcn default <namespace>` intentionally.
- Unqualified component names must fail when multiple enabled registries contain the same component.
- Use `--registry-name <namespace>` when a command operates on a specific registry.

## Automation Pattern

```bash
flutter_shadcn registries --json
flutter_shadcn default
flutter_shadcn doctor --json
flutter_shadcn search @shadcn dialog --json
flutter_shadcn dry-run @shadcn/dialog --json
flutter_shadcn add @shadcn/dialog
flutter_shadcn validate --json
flutter_shadcn audit --json
flutter_shadcn deps --json
```
