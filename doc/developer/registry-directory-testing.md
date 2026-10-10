# Registry Directory Testing (legacy)

The registry directory (`registries.json`) belonged to the v1 registry model: it mapped namespaces to `components.json`/`index.json` paths, install roots, capabilities, trust metadata, and inline init actions.

The v2 CLI resolves a single registry manifest per source instead. Installs never read a registry directory; `flutter_shadcn registries` still reads one optionally to list discoverable registries when `registriesPath` is configured.

## Testing a Registry Source

Point the CLI at a local registry root:

```bash
flutter_shadcn --registry ../my-registry registries
flutter_shadcn --registry ../my-registry init --yes
flutter_shadcn --registry ../my-registry add button
flutter_shadcn --registry ../my-registry validate
```

## Cache and Offline Behavior

Remote registry fetches use cache files under `.shadcn/cache/registry`. In `--offline` mode the CLI does not perform network calls and fails when the cache is missing.

## Recommended Test Loop

```bash
dart test test/registry_directory_test.dart
dart test test/registry_manifest_loader_test.dart
dart test test/commands_v2_test.dart
```
