# Integrity and Schema Validation

The CLI validates the registry manifest before installing from it. Invalid schema or missing files are fatal.

## Manifest Schema

The registry manifest (`manifests/registry.json`, schemaVersion 2) is validated against the v2 rules before any file is copied:

- `schemaVersion` must be `2`; required top-level keys present, no unknown keys.
- Every `deps` reference resolves to a unit in the corresponding map (primitive cycles are legal).
- `files` / `userOwned` / preset `file` are valid relPaths under the directory their owner implies.
- `fileHashes` covers every copyable file (theme presets are consumed, never copied, so they are exempt).
- When a registry root is given, every declared file exists on disk.

Run it explicitly with:

```bash
flutter_shadcn validate
flutter_shadcn --registry ../my-registry validate
```

## File Integrity

Every installed file is hashed with sha256 and recorded in `shadcn.lock`. `audit` compares the lock's hashes against disk; `doctor` combines that with closure, layout and pubspec checks:

```bash
flutter_shadcn audit
flutter_shadcn doctor
```

`update` overwrites a file only when its bytes still match the lock; a locally modified file is reported and left untouched.

## Cache Behavior

Remote registry reads are cached under `.shadcn/cache/registry`. Offline mode uses the cache only:

```bash
flutter_shadcn --offline list
```

If the cache is absent, offline commands fail. Run the same command online first to populate the cache.
