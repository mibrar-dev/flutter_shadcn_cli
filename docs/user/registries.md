# Registries

The CLI is multi-registry by default. A registry namespace identifies where a component comes from and where it should be installed.

## List Registries

```bash
flutter_shadcn registries
flutter_shadcn registries --json
```

This shows configured registries, discoverable registries from the registry directory, the default namespace, whether each registry is enabled, and available capabilities.

## Set the Default Registry

```bash
flutter_shadcn default shadcn
```

The default registry is used for unqualified component names when the component is not ambiguous.

To see the current default:

```bash
flutter_shadcn default
```

## Use a Specific Registry

```bash
flutter_shadcn add @shadcn/button
flutter_shadcn info @shadcn/button
flutter_shadcn list @shadcn
flutter_shadcn search @shadcn button
```

Use `@namespace/component` for component commands. Use `@namespace` by itself for registry browsing commands such as `list`, `search`, and `feedback`.

## Global Registry Selection

Some commands can also use the public root option:

```bash
flutter_shadcn --registry-name shadcn validate
flutter_shadcn --registry-name shadcn audit
flutter_shadcn --registry-name shadcn deps
```

Use this when the command works against the active registry rather than one explicit component.

## Offline Mode

```bash
flutter_shadcn --offline list
```

Offline mode disables network calls and uses cached data. Use it only after the needed registry data has already been fetched or configured locally.

## Registry Directory

The registry directory defines:

- namespace
- install root
- manifest paths
- capabilities
- trust metadata
- inline init actions

Reference details are in [../reference/registries-json.md](../reference/registries-json.md).
