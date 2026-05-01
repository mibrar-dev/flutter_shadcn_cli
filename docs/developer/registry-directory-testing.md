# Registry Directory Testing

The registry directory is the source of truth for registry discovery. It maps namespaces to registry roots, manifest paths, install roots, capabilities, trust metadata, and inline init actions.

## Load a Local Directory

```bash
flutter_shadcn --registries-path ./registries.json registries
flutter_shadcn --registries-path ./registries.json init shadcn --yes
flutter_shadcn --registries-path ./registries.json add @shadcn/button
```

`--registries-path` can point to:

- a `registries.json` file
- a directory containing `registries.json`

## Minimal Entry

```json
{
  "schemaVersion": 1,
  "registries": [
    {
      "id": "local_shadcn",
      "displayName": "Local shadcn",
      "maintainers": ["team"],
      "repo": "https://github.com/example/local-shadcn",
      "license": "MIT",
      "minCliVersion": "0.2.0",
      "baseUrl": "https://example.com/registry/",
      "paths": {
        "componentsJson": "components.json",
        "componentsSchemaJson": "components.schema.json"
      },
      "install": {
        "namespace": "shadcn",
        "root": "lib/ui/shadcn"
      }
    }
  ]
}
```

## Inline Init Actions

Registry entries can include bootstrap actions:

```json
{
  "init": {
    "version": 1,
    "actions": [
      {
        "type": "ensureDirs",
        "dirs": ["assets/fonts", "lib/ui/shadcn/shared"]
      },
      {
        "type": "copyFiles",
        "base": "registry",
        "destBase": "lib/ui/shadcn",
        "files": ["shared/theme/theme.dart"]
      }
    ]
  }
}
```

Run `init` to test inline actions:

```bash
flutter_shadcn --registries-path ./registries.json init shadcn --yes
```

## Cache and Offline Behavior

Remote registry directory fetches use cache files under `.shadcn/cache`. When the server returns an ETag, the CLI reuses it for later requests. If a remote fetch fails and stale cache exists, the CLI can fall back to cached data. In `--offline` mode, the CLI does not perform network calls and fails when required cached files are missing.

## Recommended Test Loop

```bash
dart test test/registry_directory_test.dart
dart test test/init_action_engine_test.dart
dart test test/multi_registry_manager_test.dart
```

Then verify from a throwaway Flutter app:

```bash
flutter_shadcn --registries-path ./registries.json registries
flutter_shadcn --registries-path ./registries.json init shadcn --yes
flutter_shadcn --registries-path ./registries.json add @shadcn/button
flutter_shadcn --registries-path ./registries.json validate
```
