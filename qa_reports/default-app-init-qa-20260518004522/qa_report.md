# Default App Init QA Report

Date: 2026-05-18

## Scope

Validated which bootstrap components should install during interactive `init`:

- Install by default: lean `layout/app` wrapper files.
- Install by default as runtime support: shared `localizations` base/English delegate files, shared `theme`, shared `overlay`, and shared utilities required by `ShadcnApp`.
- Do not install by default: `layout/scaffold`.
- Do not install by default: `display/divider`.
- Do not install by default: `utility/shadcn_localizations`, `utility/shadcn_localizations_en`, and `utility/shadcn_localizations_extensions` component folders.
- Do not install by default: icon/font assets unless selected interactively.

## Before

`layout/app` declared component dependencies on `scaffold`, `divider`, and `shadcn_localizations`, and exported `Scaffold`, `AppBar`, and `Divider` from `app.dart`. That made init/install pull UI components that are not needed for the app wrapper itself.

## Now

`layout/app` is a lean bootstrap component. It installs only:

- `app.dart`
- `_impl/core/shadcn_ui.dart`
- `component_theme_global_configs.dart`

The registry init action supplies only shared runtime support required by `ShadcnApp`. Scaffold, divider, localization extension helpers, and font/icon assets stay out of the default init path.

## Manual Interactive Test

Command:

```bash
flutter create --quiet default_app_init
cd default_app_init
printf '\n\n\n\n' | dart /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/bin/shadcn.dart --advanced init --registries-path /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/registry-directory/registries/registries.json --registry-path /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/lib/registry
```

Result:

- Interactive component path prompt accepted default `lib/ui/shadcn`.
- Interactive shared path prompt accepted default `lib/ui/shadcn/shared`.
- Optional font/icon group prompt accepted Enter and copied `0` asset files.
- Theme prompt accepted Enter and skipped theme selection.
- Init completed with `81` files and `1` directory.

## File Assertions

Required files existed:

- `lib/ui/shadcn/components/layout/app/app.dart`
- `lib/ui/shadcn/components/layout/app/_impl/core/shadcn_ui.dart`
- `lib/ui/shadcn/components/layout/app/component_theme_global_configs.dart`
- `lib/ui/shadcn/shared/localizations/shadcn_localizations.dart`
- `lib/ui/shadcn/shared/primitives/overlay.dart`
- `lib/ui/shadcn/shared/theme/theme.dart`
- `lib/ui/shadcn/shared/utils/constants.dart`

Forbidden default files/folders did not exist:

- `lib/ui/shadcn/components/layout/scaffold/scaffold.dart`
- `lib/ui/shadcn/components/display/divider/divider.dart`
- `lib/ui/shadcn/shared/localizations/shadcn_localizations_extensions.dart`
- `lib/ui/shadcn/components/utility/shadcn_localizations`
- `assets/fonts`

## Analyzer Verification

`lib/main.dart` was changed in the temp app to use:

```dart
import 'package:flutter/widgets.dart';

import 'ui/shadcn/components/layout/app/app.dart';

void main() {
  runApp(const ShadcnApp(home: SizedBox.shrink()));
}
```

Command:

```bash
flutter analyze lib
```

Result:

```text
No issues found!
```

The full project analyzer only failed because the default Flutter template test still referenced the replaced starter `MyApp`; this is unrelated to generated shadcn files.

## Registry Validation

Command:

```bash
dart /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_cli/bin/shadcn.dart --advanced validate --registries-path /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/registry-directory/registries/registries.json --registry-path /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/lib/registry --json
```

Result:

- Schema valid: yes.
- Components checked: `133`.
- Files checked: `1834`.
- Missing dependencies: `0`.
- Missing files: `0`.

## Score

Pass rate: 100%.

