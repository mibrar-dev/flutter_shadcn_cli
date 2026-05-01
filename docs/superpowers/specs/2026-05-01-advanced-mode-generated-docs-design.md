# Advanced Mode and Generated Command Docs Design

## Goal

Keep `flutter_shadcn` user-focused by default while providing a single opt-in flag for developer and experimental surfaces, and replace hand-maintained command reference pages with generated markdown that stays synchronized with CLI metadata.

## Decisions

- Use `--advanced` as the single opt-in global flag.
- Parse `--advanced` position-flexibly anywhere in argv.
- Keep `theme --apply <id>` public.
- Gate only theme file and URL imports: `theme --apply-file`, `theme --apply-url`, `theme widget --apply-file`, and `theme widget --apply-url`.
- Gate developer flags: `--registry-path`, `--registry-url`, `--registries-path`, and `--skip-integrity`.
- Gate tooling commands: `docs` and `install-skill`.
- Keep diagnostics public: `doctor`, `validate`, `audit`, `deps`, and `dry-run`.
- Rename the docs root from `doc/` to `docs/`.
- Commit generated command reference markdown under `docs/reference/commands/`.
- Make `flutter_shadcn --advanced docs --generate` regenerate command docs.
- Make stale-doc verification fast and obvious, with the failure message telling maintainers exactly which command to run.

## User Experience

Default help stays focused on normal user workflows. It shows public commands and public global flags only.

```bash
flutter_shadcn --help
```

Advanced help shows developer and experimental surfaces.

```bash
flutter_shadcn --advanced --help
flutter_shadcn docs --advanced --help
```

Advanced mode is position-flexible. These are equivalent:

```bash
flutter_shadcn --advanced docs --generate
flutter_shadcn docs --advanced --generate
```

If an advanced-only command or flag is used without `--advanced`, the CLI fails with a clear error:

```text
The docs command requires --advanced.
Run: flutter_shadcn --advanced docs --generate
```

## Advanced Gate Scope

Advanced-only global flags:

- `--registry-path <path>`
- `--registry-url <url>`
- `--registries-path <path>`
- `--skip-integrity`

Advanced-only commands:

- `docs`
- `install-skill`

Advanced-only command flags:

- `theme --apply-file <path>`
- `theme --apply-url <url>`
- `theme widget --apply-file <path>`
- `theme widget --apply-url <url>`

Public theme behavior must remain public:

- `theme --list`
- `theme --refresh`
- `theme --apply <id>`
- `theme <id>`
- `theme widget --list`
- `theme widget --list-targets`
- `theme widget --reset`

Normal theme help must not list advanced file or URL import flags. Advanced theme help may list them.

## Parser Design

Add a lightweight normalization step that scans the full argv for `--advanced` before command routing. The scanner should remove `--advanced` from the argv passed to the underlying parser so command parsers do not reject it when it appears after a subcommand.

The parsed execution context should expose:

```dart
class CliAdvancedMode {
  final bool enabled;
  const CliAdvancedMode({required this.enabled});
}
```

The implementation may use a simpler helper if that better matches current parser style, but the behavior must be explicit and tested.

Developer flags remain hidden from normal help. They become available only when advanced mode is enabled. A hidden flag without `--advanced` should produce an advanced-gate error, not silently route or fall back.

## Command Metadata Design

Extend command metadata so docs and usage can be generated from one source. The source of truth should live in Dart code next to the CLI command registry, not in a YAML or JSON sidecar, so command visibility, grouping, and docs metadata change in the same review as parser or dispatcher changes.

Add a focused metadata model near the existing command registry, for example `lib/src/presentation/cli/command_metadata.dart`, and have `command_registry.dart`, usage output, docs generation, and command-doc freshness tests read from it.

The metadata should cover:

- command id
- aliases
- group slug
- sort order within the group
- one-line description
- visibility: public or advanced
- usage
- arguments
- flags
- examples
- notes
- see-also links

Generated docs should use this metadata instead of scraping help text.

Group and command ordering must be encoded in metadata. Use explicit group order plus a per-command `sortOrder` integer so the generated index is deterministic and reflects user workflow order rather than alphabetic order.

## Docs Structure

Rename existing docs from `doc/` to `docs/`.

Target tree:

```text
docs/
  index.md
  installation.md
  getting-started.md
  troubleshooting.md
  changelog.md
  user/
    commands.md
    components.md
    getting-started.md
    registries.md
    troubleshooting.md
  developer/
    advanced-mode.md
    local-registry-development.md
    registry-directory-testing.md
    integrity-and-schema-validation.md
    experimental-features.md
  guides/
    component-workflow.md
    registry-setup.md
    diagnostics.md
    advanced-workflows.md
  reference/
    config-state.md
    registries-json.md
    inline-init-actions.md
    manual-testing-guide.md
    commands/
      index.md
      components/
        add.md
        remove.md
        dry-run.md
        list.md
        search.md
        info.md
      project/
        init.md
        registries.md
        default.md
        sync.md
        assets.md
        theme.md
        platform.md
      diagnostics/
        doctor.md
        validate.md
        audit.md
        deps.md
      tooling/
        feedback.md
        version.md
        upgrade.md
      advanced/
        docs.md
        install-skill.md
```

No generated command group should nest deeper than `docs/reference/commands/<group>/<command>.md`.

## Generated `commands/index.md`

The generated index should be the master command cheat sheet. It should contain one section per group. Groups and commands should be sorted by the explicit order values defined in command metadata, not alphabetically.

Each bullet should use this format:

```markdown
- [`flutter_shadcn add`](./components/add.md) - Install one or more components.
```

Advanced commands should appear under an `Advanced` section with a short note that they require `--advanced`.

## Command Page Template

Each generated command page should follow this structure:

~~~markdown
# flutter_shadcn add

> Install one or more components.

## Usage

```bash
flutter_shadcn add <component...> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<component...>` | Yes | Component names or `@namespace/component` addresses. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--all` | `-a` | `false` | Install every available component. |

## Examples

```bash
flutter_shadcn add button
flutter_shadcn add @shadcn/button
```

## Notes

Use namespaced addresses when multiple registries provide the same component.

## See Also

- [`flutter_shadcn remove`](../components/remove.md)
~~~

## Stale Docs Test

The stale-docs test should:

- generate command docs into a temporary directory
- compare generated output with committed files under `docs/reference/commands/`
- fail quickly without running Flutter or network work
- print the exact fix command:

```text
Generated command docs are stale.
Run: dart run bin/flutter_shadcn.dart --advanced docs --generate
```

Disabling this test should be treated as a release-risk decision because it is the safeguard that keeps generated reference docs honest.

## Testing Requirements

Parser and gate tests:

- `--advanced` is accepted before the command.
- `--advanced` is accepted after the command.
- developer flags fail without `--advanced`.
- developer flags work with `--advanced`.
- `docs` and `install-skill` fail without `--advanced`.
- `docs` and `install-skill` work with `--advanced`.
- `theme --apply <id>` works without `--advanced`.
- `theme --apply-file` and `theme --apply-url` fail without `--advanced`.
- `theme --apply-file` and `theme --apply-url` work with `--advanced`.
- normal theme help excludes advanced import flags.
- advanced theme help includes advanced import flags.

Docs tests:

- generated command docs are current.
- command matrix reads `docs/user/commands.md`.
- README links point to `docs/`.
- no `doc/` paths remain in code or docs, except historical text if deliberately retained in changelog.

## Non-Goals

- Do not add a second docs root.
- Do not revive `doc/site/`.
- Do not gate normal diagnostics.
- Do not make `namespace:component` public in docs.
- Do not hand-write generated command pages after the generator exists.
