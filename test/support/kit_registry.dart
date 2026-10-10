import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The `flutter_shadcn_kit` package root used by the cross-repo tests.
///
/// Located next to this repository (`../shadcn_flutter_kit/flutter_shadcn_kit`)
/// and overridable with `SHADCN_KIT_ROOT`. Returns `null` when the kit is not
/// checked out, so the CLI package stays testable on its own.
String? findKitPackageRoot() {
  final override = Platform.environment['SHADCN_KIT_ROOT'];
  final candidates = <String>[
    if (override != null && override.trim().isNotEmpty) override,
    p.normalize(
      p.join(Directory.current.path, '..', 'shadcn_flutter_kit',
          'flutter_shadcn_kit'),
    ),
    p.normalize(
      p.join(Directory.current.path, '..', '..', 'shadcn_flutter_kit',
          'flutter_shadcn_kit'),
    ),
  ];
  for (final candidate in candidates) {
    if (File(p.join(candidate, 'tool', 'rearch', 'gen_app_theme.dart'))
        .existsSync()) {
      return p.normalize(candidate);
    }
  }
  return null;
}

/// Registry-relative path of a preset inside the kit.
String kitPresetPath(String root, String id) =>
    p.join(root, 'lib', 'registry', 'themes', '$id.json');

/// Every preset id published by the kit registry manifest.
List<String> kitPresetIds(String root) {
  final manifest =
      File(p.join(root, 'lib', 'registry', 'manifests', 'registry.json'))
          .readAsStringSync();
  final decoded = jsonDecode(manifest) as Map<String, dynamic>;
  final themes = decoded['themes']! as Map<String, dynamic>;
  return themes.keys.toList()..sort();
}

/// Decoded `lib/registry/manifests/registry.json` from the kit.
Map<String, dynamic> kitRegistryManifest(String root) {
  final source =
      File(p.join(root, 'lib', 'registry', 'manifests', 'registry.json'))
          .readAsStringSync();
  return jsonDecode(source) as Map<String, dynamic>;
}

/// Decoded `themes/<id>.json` from the kit.
Map<String, dynamic> kitPresetJson(String root, String id) =>
    jsonDecode(File(kitPresetPath(root, id)).readAsStringSync())
        as Map<String, dynamic>;
