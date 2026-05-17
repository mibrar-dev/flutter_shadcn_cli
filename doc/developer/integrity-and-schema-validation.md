# Integrity and Schema Validation

The CLI validates registry metadata before installing from it. Public commands treat invalid schema and integrity failures as fatal. Developer bypasses exist only for unpublished local work.

## Validation Layers

There are three separate validation layers:

1. Registry directory schema validation
2. Component manifest schema validation
3. `components.json` integrity pinning

## Registry Directory Schema

`registries.json` is validated against the registry directory schema when loaded. This applies to remote directory URLs and local `--registries-path` files.

If the directory is invalid, discovery and namespace init should fail before install actions run.

## Component Manifest Schema

Registry component data is loaded from `paths.componentsJson`, usually `components.json`.

Schema behavior:

- Explicit schema path missing or invalid: fatal.
- `$schema` in `components.json` missing or invalid: fatal.
- Implicit `components.schema.json` missing: fatal.
- Invalid `components.json`: fatal.
- `--skip-integrity`: bypasses component schema validation.

## Integrity Pinning

Registry directory entries may declare trust metadata. When `trust.mode` is `sha256`, the fetched `components.json` body is hashed and compared against the configured digest.

Use a lowercase hex SHA-256 digest:

```json
{
  "trust": {
    "mode": "sha256",
    "sha256": "0123456789abcdef..."
  }
}
```

`--skip-integrity` bypasses integrity checks and schema validation. Do not use it in public documentation or production install instructions.

## Developer Bypass

For unpublished local work:

```bash
flutter_shadcn --skip-integrity --registry-path ../registry/registry add @shadcn/button
```

Use this only while authoring registry files. Before publishing, remove the bypass and verify:

```bash
flutter_shadcn --registry-path ../registry/registry validate
flutter_shadcn --registry-path ../registry/registry add @shadcn/button
```

## Cache Behavior

Remote directory and component fetches can use `.shadcn/cache`. Offline mode uses cached files only:

```bash
flutter_shadcn --offline list
```

If cache is absent or stale data is unusable, offline commands fail. Run the same command online first to populate cache.
