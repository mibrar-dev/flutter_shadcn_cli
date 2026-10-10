import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_block.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_component.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/manifest_unit.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/theme_preset.dart';

/// Top-level models for the generated `lib/registry/manifests/registry.json`
/// (schemaVersion 2). One manifest replaces the v1 `components.json` +
/// `index.json` + `theme.index.json` + `shared_manifest.json` + per-component
/// `meta.json` resolution.

/// Directory name of the blocks layer under the install root. Fixed by the
/// schema (`const`), so the CLI never guesses it.
const String kManifestBlocksDir = 'blocks';

/// `registry` block: which registry this manifest describes.
class RegistryInfo {
  final String name;
  final String version;
  final String? ref;
  final String? generatedAt;

  const RegistryInfo({
    required this.name,
    required this.version,
    this.ref,
    this.generatedAt,
  });

  factory RegistryInfo.fromJson(Map<String, dynamic> json) {
    return RegistryInfo(
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '',
      ref: json['ref'] as String?,
      generatedAt: json['generatedAt'] as String?,
    );
  }
}

/// `install` block: where the CLI places the tree. Layer dirs and
/// componentsDir preserve the registry depth so the relative imports inside
/// copied files stay valid (plan §3).
class ManifestLayerDirs {
  final String foundation;
  final String theme;
  final String primitives;

  const ManifestLayerDirs({
    required this.foundation,
    required this.theme,
    required this.primitives,
  });

  factory ManifestLayerDirs.fromJson(Map<String, dynamic> json) {
    return ManifestLayerDirs(
      foundation: json['foundation'] as String? ?? '',
      theme: json['theme'] as String? ?? '',
      primitives: json['primitives'] as String? ?? '',
    );
  }
}

class ManifestInstall {
  final String root;
  final String componentsDir;
  final String blocksDir;
  final ManifestLayerDirs layerDirs;
  final String userOwnedSuffix;

  const ManifestInstall({
    required this.root,
    required this.componentsDir,
    required this.layerDirs,
    required this.userOwnedSuffix,
    this.blocksDir = kManifestBlocksDir,
  });

  factory ManifestInstall.fromJson(Map<String, dynamic> json) {
    return ManifestInstall(
      root: json['root'] as String? ?? '',
      componentsDir: json['componentsDir'] as String? ?? '',
      blocksDir: json['blocksDir'] as String? ?? kManifestBlocksDir,
      layerDirs: json['layerDirs'] is Map
          ? ManifestLayerDirs.fromJson(
              (json['layerDirs'] as Map)
                  .map((key, value) => MapEntry(key.toString(), value)),
            )
          : const ManifestLayerDirs(
              foundation: '',
              theme: '',
              primitives: '',
            ),
      userOwnedSuffix: json['userOwnedSuffix'] as String? ?? '',
    );
  }
}

/// The whole registry manifest. Parse with [RegistryManifest.fromJson];
/// validate the raw JSON first with `ManifestSchemaValidator.validate`.
class RegistryManifest {
  final int schemaVersion;
  final RegistryInfo registry;
  final ManifestInstall install;
  final Map<String, ManifestUnit> foundation;
  final Map<String, ManifestUnit> theme;
  final Map<String, ManifestPrimitive> primitives;
  final Map<String, ManifestComponent> components;

  /// Installable blocks (registry layer 4), keyed by id.
  ///
  /// Absent in a manifest written before the blocks layer existed; the CLI
  /// treats that as "no blocks" so older registries keep working.
  final Map<String, ManifestBlock> blocks;

  final Map<String, ThemePreset> themes;
  final Map<String, String> fileHashes;

  const RegistryManifest({
    required this.schemaVersion,
    required this.registry,
    required this.install,
    required this.foundation,
    required this.theme,
    required this.primitives,
    required this.components,
    required this.blocks,
    required this.themes,
    required this.fileHashes,
  });

  factory RegistryManifest.fromJson(Map<String, dynamic> json) {
    Map<String, T> units<T extends ManifestUnit>(
      Object? raw,
      T Function(String id, Map<String, dynamic> entry) parse,
    ) {
      if (raw is! Map) {
        return const {};
      }
      return raw.map((key, value) {
        final id = key.toString();
        final entry = (value as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v),
            ) ??
            const <String, dynamic>{};
        return MapEntry(id, parse(id, entry));
      });
    }

    Map<String, ThemePreset> presets(Object? raw) {
      if (raw is! Map) {
        return const {};
      }
      return raw.map((key, value) {
        final id = key.toString();
        final entry = (value as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v),
            ) ??
            const <String, dynamic>{};
        return MapEntry(id, ThemePreset.fromJson(id, entry));
      });
    }

    Map<String, String> hashes(Object? raw) {
      if (raw is! Map) {
        return const {};
      }
      return raw.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }

    return RegistryManifest(
      schemaVersion: json['schemaVersion'] as int? ?? 0,
      registry: json['registry'] is Map
          ? RegistryInfo.fromJson(
              (json['registry'] as Map)
                  .map((key, value) => MapEntry(key.toString(), value)),
            )
          : const RegistryInfo(name: '', version: ''),
      install: json['install'] is Map
          ? ManifestInstall.fromJson(
              (json['install'] as Map)
                  .map((key, value) => MapEntry(key.toString(), value)),
            )
          : const ManifestInstall(
              root: '',
              componentsDir: '',
              layerDirs: ManifestLayerDirs(
                foundation: '',
                theme: '',
                primitives: '',
              ),
              userOwnedSuffix: '',
            ),
      foundation: units(json['foundation'], ManifestUnit.fromJson),
      theme: units(json['theme'], ManifestUnit.fromJson),
      primitives: units(json['primitives'], ManifestPrimitive.fromJson),
      components: (json['components'] as Map?)?.map((key, value) {
            final id = key.toString();
            final entry = (value as Map?)?.map(
                  (k, v) => MapEntry(k.toString(), v),
                ) ??
                const <String, dynamic>{};
            return MapEntry(id, ManifestComponent.fromJson(id, entry));
          }) ??
          const {},
      blocks: (json['blocks'] as Map?)?.map((key, value) {
            final id = key.toString();
            final entry = (value as Map?)?.map(
                  (k, v) => MapEntry(k.toString(), v),
                ) ??
                const <String, dynamic>{};
            return MapEntry(id, ManifestBlock.fromJson(id, entry));
          }) ??
          const {},
      themes: presets(json['themes']),
      fileHashes: hashes(json['fileHashes']),
    );
  }

  /// Every copyable relPath declared by the manifest: all layer unit files,
  /// every component's files + userOwned, every block's files and every theme
  /// preset file. A block's `docs` entries are deliberately absent: they are
  /// never copied into an app.
  Set<String> get declaredFiles {
    final paths = <String>{};
    for (final unit in [...foundation.values, ...theme.values]) {
      paths.addAll(unit.files);
    }
    for (final primitive in primitives.values) {
      paths.addAll(primitive.files);
    }
    for (final component in components.values) {
      paths.addAll(component.allFiles);
    }
    for (final block in blocks.values) {
      paths.addAll(block.allFiles);
    }
    for (final preset in themes.values) {
      paths.add(preset.file);
    }
    return paths;
  }
}
