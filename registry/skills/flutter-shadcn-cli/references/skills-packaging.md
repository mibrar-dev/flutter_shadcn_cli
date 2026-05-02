# Skill Packaging Rules

## Packaged Layout

```text
registry/
  skills/
    skills.json
    flutter-shadcn-cli/
      SKILL.md
      INSTALLATION.md
      skill.json
      references/
    flutter-shadcn-ui/
      SKILL.md
      INSTALLATION.md
      skill.json
      references/
```

This path is included in the pub.dev package and is discoverable from the resolved package root.

## Manifest Rules

- `skill.json` is used by the CLI to decide what to copy.
- `SKILL.md`, `INSTALLATION.md`, and reference markdown files are copied to model folders.
- Management files such as `skill.json`, `skill.yaml`, and schema references are not copied to model folders.
- Use `files.references` for agent-readable docs.

## Install Commands

```bash
flutter_shadcn --advanced install-skill --available
flutter_shadcn --advanced install-skill --skill flutter-shadcn-cli --model .codex
flutter_shadcn --advanced install-skill --skill flutter-shadcn-ui --model .codex
flutter_shadcn --advanced install-skill --list
```

## Remote Sources

`--skills-url` may point at a skills root:

```bash
flutter_shadcn --advanced install-skill \
  --skills-url https://raw.githubusercontent.com/ibrar-x/shadcn_flutter_kit/main/flutter_shadcn_kit/skills \
  --skill flutter-shadcn-ui \
  --model .codex
```

GitHub `tree` URLs are normalized to raw content URLs by the installer.
