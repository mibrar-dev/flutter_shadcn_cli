# Inline Init Actions Reference

Inline init actions live in `registries.json` under `registries[].init.actions`. They let a registry bootstrap directories, shared files, assets, fonts, dependencies, and user-facing messages during `flutter_shadcn init`.

The engine supports these action types:

- `ensureDirs`
- `copyFiles`
- `copyDir`
- `mergePubspec`
- `message`

All destination paths are project-relative and pass through the same path guard used by installer writes. Absolute paths, traversal, and symlink escapes are rejected.

## `message`

Prints informational lines during init.

```json
{
  "type": "message",
  "lines": [
    "Installed shadcn shared files.",
    "Run flutter pub get before launching the app."
  ]
}
```

Fields:

- `lines`: required list of strings

## `ensureDirs`

Creates project directories if they do not already exist.

```json
{
  "type": "ensureDirs",
  "dirs": [
    "assets/fonts",
    "lib/ui/shadcn"
  ]
}
```

Fields:

- `dirs`: list of project-relative directories

## `copyFiles`

Copies a known set of files from the registry into the project.

```json
{
  "type": "copyFiles",
  "base": "registry",
  "destBase": "lib/ui/shadcn",
  "files": [
    "shared/theme/theme.dart",
    "shared/tokens/tokens.dart"
  ],
  "overwrite": false
}
```

Fields:

- `base`: optional registry source base
- `destBase`: optional project destination base
- `files`: required list of file paths when no `from`/`to` mapping is used
- `overwrite`: optional boolean, defaults to `false`

`base` and `destBase` must be provided together. When present, the source path is resolved under `base` and the destination is resolved under `destBase`.

## `copyFiles` With Directory Mapping

Use `from` and `to` when registry source paths need to move into a different project destination.

```json
{
  "type": "copyFiles",
  "base": "registry",
  "destBase": "lib/ui/shadcn",
  "from": "shared",
  "to": "shared",
  "files": [
    "theme/theme.dart",
    "tokens/tokens.dart"
  ]
}
```

Fields:

- `from`: source subdirectory
- `to`: destination subdirectory
- `files`: file list relative to `from`

`from` and `to` must be provided together. With directory mapping, provide exactly one of `files` or `index`.

## `copyDir`

`copyDir` uses the same copy engine as `copyFiles`, but is intended for directory-style copies. It can load its file list from an index JSON.

```json
{
  "type": "copyDir",
  "base": "registry",
  "destBase": "lib/ui/shadcn",
  "from": "shared",
  "to": "shared",
  "index": "shared/index.json"
}
```

The index file must be a JSON object with a `files` list:

```json
{
  "files": [
    "theme/theme.dart",
    "tokens/tokens.dart"
  ]
}
```

## `mergePubspec`

Merges dependencies, dev dependencies, Flutter assets, and Flutter fonts into `pubspec.yaml`.

```json
{
  "type": "mergePubspec",
  "dependencies": {
    "collection": "^1.18.0"
  },
  "devDependencies": {
    "flutter_lints": "^4.0.0"
  },
  "flutterAssets": [
    "assets/fonts/"
  ],
  "flutterFonts": [
    {
      "family": "Inter",
      "fonts": [
        {
          "asset": "assets/fonts/Inter-Regular.ttf",
          "weight": 400
        },
        {
          "asset": "assets/fonts/Inter-Italic.ttf",
          "weight": 400,
          "style": "italic"
        }
      ]
    }
  ]
}
```

Fields:

- `dependencies`: map written under `dependencies`
- `devDependencies`: map written under `dev_dependencies`
- `flutterAssets`: list merged under `flutter.assets`
- `flutterFonts`: list merged under `flutter.fonts`

Existing entries are not duplicated.

## Rollback

The init engine records directories created, files written, and `pubspec.yaml` additions. If a later action fails, rollback can remove written files, remove empty directories created during the run, and undo recorded `pubspec.yaml` additions.

Rollback only applies to changes recorded by the inline init engine. It does not delete user-authored files that were already present before the command.
