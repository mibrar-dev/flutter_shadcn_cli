# Local Registry Development

This page is for registry authors testing unpublished registry content. The flags here are hidden from public help and should not appear in user-facing examples.

## Hidden Developer Flags

```bash
flutter_shadcn --registry-path ../my-registry/registry add button
flutter_shadcn --registry-url http://localhost:8080/registry/ add button
flutter_shadcn --registries-path ./registries.json init shadcn --yes
flutter_shadcn --skip-integrity --registry-path ../my-registry/registry add button
```

Flags:

- `--registry-path <path>`: use a local registry root for the selected namespace.
- `--registry-url <url>`: use a remote registry root for the selected namespace.
- `--registries-path <path>`: use a local registry directory file or a directory containing `registries.json`.
- `--skip-integrity`: bypass component schema validation and integrity checks.

`--registry-path` and `--registry-url` are mutually exclusive. Use one source override at a time.

## Flag Placement

Developer flags are root flags, but the parser hoists them when passed after a subcommand. These are equivalent:

```bash
flutter_shadcn --registries-path ./registries.json init shadcn --yes
flutter_shadcn init shadcn --registries-path ./registries.json --yes
```

Prefer root placement in scripts because it is clearer.

## Local Registry Layouts

The local override can point directly at a `registry` folder:

```text
my-registry/
  registry/
    components.json
    components.schema.json
    components/
      button/
        button.dart
```

It can also point at a registry folder with manifests under `manifests/`:

```text
my-registry/
  registry/
    manifests/
      components.json
      components.schema.json
    components/
      button/
        button.dart
```

When the local path basename is `registry`, inline action file sources can resolve relative to the parent source root. This supports registry entries that use paths like `registry/shared/theme/theme.dart`.

## Component Manifest Detection

For local overrides, the CLI detects common component manifest locations:

- `manifests/components.json`
- `components.json`
- `registry/manifests/components.json`
- `registry/components.json`

If your registry uses a custom path, set it in the registry directory entry under `paths.componentsJson`.

## Testing a Local Registry

Persist local development mode once:

```bash
flutter_shadcn --advanced default shadcn --local
```

This prompts for:

- the local `registries.json` path
- the local registry root

After that, regular commands use the saved local paths until you switch back:

```bash
flutter_shadcn init --yes
flutter_shadcn add @shadcn/button
flutter_shadcn --advanced default shadcn --remote
```

Use a local registry directory file:

```bash
flutter_shadcn --registries-path ./registries.json registries
flutter_shadcn --registries-path ./registries.json init shadcn --yes
flutter_shadcn --registries-path ./registries.json add @shadcn/button
```

Use a local registry source override:

```bash
flutter_shadcn --registry-path ../my-registry/registry add @shadcn/button
flutter_shadcn --registry-path ../my-registry/registry validate
```

Use `--skip-integrity` only while the schema or trust metadata is still being authored:

```bash
flutter_shadcn --skip-integrity --registry-path ../my-registry/registry add @shadcn/button
```

Do not publish registry directory entries that require `--skip-integrity`.
