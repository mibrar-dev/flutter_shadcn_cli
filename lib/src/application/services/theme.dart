/// Theme flow for registry manifest v2: preset JSON -> `theme/app_theme.dart`.
///
/// `app_theme_values.dart` + `app_theme_generator.dart` are a byte-for-byte
/// port of the kit's `tool/rearch/gen_app_theme.dart`, so the CLI and the kit
/// emit the same values-only file; `theme_service.dart` adds the v2 rules on
/// top (manifest `themes` map, `themes.schema.json` validation, lock v2
/// recording and the user-owned `app_theme.dart` drift policy).
library;

export 'package:flutter_shadcn_cli/src/application/services/theme/app_theme_generator.dart';
export 'package:flutter_shadcn_cli/src/application/services/theme/app_theme_values.dart';
export 'package:flutter_shadcn_cli/src/application/services/theme/theme_models.dart';
export 'package:flutter_shadcn_cli/src/application/services/theme/theme_preset_validator.dart';
export 'package:flutter_shadcn_cli/src/application/services/theme/theme_registry_source.dart';
export 'package:flutter_shadcn_cli/src/application/services/theme/theme_service.dart';
