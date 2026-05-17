/// Public metadata helpers exported by `flutter_shadcn_cli`.
///
/// Most users interact with this package through the `flutter_shadcn` or
/// `shadcn` executables after global activation:
///
/// ```bash
/// dart pub global activate flutter_shadcn_cli
/// flutter_shadcn init --yes
/// flutter_shadcn add button
/// ```
///
/// The library API intentionally stays small. It exposes bundled registry
/// theme preset metadata for tooling that wants to inspect preset ids, names,
/// and token maps without shelling out to the CLI.
library;

export 'registry/shared/theme/preset_theme_data.dart';
