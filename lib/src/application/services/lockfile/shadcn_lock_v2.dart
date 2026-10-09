import 'package:flutter_shadcn_cli/src/application/services/lockfile/lock_file_exception.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/lock_install_state.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/lock_json.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/lock_layer.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_component.dart';

/// The only supported lock format version.
const int kLockfileVersion = 2;

/// `shadcn.lock` lockfileVersion 2 (P5_CLI_PLAN.md §4).
///
/// Clean break: there is no v1 compatibility path and nothing is synthesised
/// from the deleted `.shadcn/components/*.json` files.
class ShadcnLock {
  const ShadcnLock({
    this.lockfileVersion = kLockfileVersion,
    this.registry = const ShadcnLockRegistry(),
    this.installRoot = '',
    this.theme,
    this.layers = const {},
    this.components = const [],
  });

  /// Parses a lock document, rejecting anything that is not v2.
  factory ShadcnLock.fromJson(
    Map<String, dynamic> json, {
    String sourcePath = kLockFileName,
  }) {
    final version = (json['lockfileVersion'] as num?)?.toInt();
    if (version != kLockfileVersion) {
      throw LockFileException(
        'Unsupported lockfileVersion ${version ?? '(missing)'}; expected '
        '$kLockfileVersion. shadcn.lock v1 is no longer supported: delete '
        'the file and re-run `shadcn init`.',
        sourcePath,
      );
    }
    final layers = <LockLayer, LockLayerState>{};
    final layersJson = json['layers'];
    if (layersJson != null && layersJson is! Map) {
      throw LockFileException('`layers` must be an object.', sourcePath);
    }
    if (layersJson is Map) {
      layersJson.forEach((key, value) {
        final layer = LockLayer.fromKey(key.toString());
        if (layer == null) {
          return;
        }
        if (value is! Map<String, dynamic>) {
          throw LockFileException(
            '`layers.$key` must be an object.',
            sourcePath,
          );
        }
        layers[layer] = LockLayerState.fromJson({
          ...value,
          'layer': layer.key,
        }, sourcePath: sourcePath);
      });
    }
    final componentsJson = json['components'];
    if (componentsJson != null && componentsJson is! List) {
      throw LockFileException('`components` must be an array.', sourcePath);
    }
    return ShadcnLock(
      registry: json['registry'] is Map<String, dynamic>
          ? ShadcnLockRegistry.fromJson(
              json['registry']! as Map<String, dynamic>,
              sourcePath: sourcePath,
            )
          : const ShadcnLockRegistry(),
      installRoot: normalizeLockPath(json['installRoot']?.toString() ?? ''),
      theme: json['theme'] is Map<String, dynamic>
          ? LockThemeSelection.fromJson(
              json['theme']! as Map<String, dynamic>,
              sourcePath: sourcePath,
            )
          : null,
      layers: layers,
      components: componentsJson is List
          ? componentsJson
              .whereType<Map<String, dynamic>>()
              .map(
                (component) => ShadcnLockComponent.fromJson(
                  component,
                  sourcePath: sourcePath,
                ),
              )
              .toList()
          : const [],
    );
  }

  final int lockfileVersion;
  final ShadcnLockRegistry registry;

  /// Project relative install root, e.g. `lib/ui/shadcn`.
  final String installRoot;

  final LockThemeSelection? theme;
  final Map<LockLayer, LockLayerState> layers;
  final List<ShadcnLockComponent> components;

  /// State of [layer]; empty when the layer was never installed.
  LockLayerState layerState(LockLayer layer) =>
      layers[layer] ?? const LockLayerState();

  List<String> get componentIds =>
      components.map((component) => component.id).toList()..sort();

  bool get isEmpty =>
      components.isEmpty && layers.values.every((l) => l.isEmpty);

  /// Every registry-owned path: layer files, component files and the
  /// generated theme file.
  Set<String> get registryOwnedPaths => {
        for (final layer in LockLayer.values) ...layerState(layer).files.keys,
        for (final component in components) ...component.files.keys,
        if (theme != null && theme!.path.isNotEmpty) theme!.path,
      };

  /// Every user-owned path; never updatable, never deleted.
  Set<String> get userOwnedPaths => {
        for (final component in components) ...component.userOwnedPaths,
      };

  /// Registry-owned paths minus user-owned ones: exactly what `update` may
  /// overwrite.
  Set<String> get updatablePaths =>
      registryOwnedPaths.difference(userOwnedPaths);

  bool isUserOwned(String path) => userOwnedPaths.contains(path);

  /// Component id, or layer key, that owns [path]; `null` when unowned.
  String? ownerOf(String path) {
    final normalized = normalizeLockPath(path);
    for (final component in components) {
      if (component.allPaths.contains(normalized)) {
        return component.id;
      }
    }
    if (theme != null && theme!.path == normalized) {
      return LockLayer.theme.key;
    }
    for (final layer in LockLayer.values) {
      if (layerState(layer).files.containsKey(normalized)) {
        return layer.key;
      }
    }
    return null;
  }

  /// Component ids that own at least one of [paths] in any role.
  Set<String> dependentsOf(Set<String> paths) {
    return {
      for (final component in components)
        if (component.ownsAny(paths)) component.id,
    };
  }

  ShadcnLock copyWith({
    ShadcnLockRegistry? registry,
    String? installRoot,
    LockThemeSelection? theme,
    bool clearTheme = false,
    Map<LockLayer, LockLayerState>? layers,
    List<ShadcnLockComponent>? components,
  }) {
    return ShadcnLock(
      lockfileVersion: lockfileVersion,
      registry: registry ?? this.registry,
      installRoot: installRoot ?? this.installRoot,
      theme: clearTheme ? null : (theme ?? this.theme),
      layers: layers ?? this.layers,
      components: components ?? this.components,
    );
  }

  ShadcnLock withRegistry(ShadcnLockRegistry value) =>
      copyWith(registry: value);

  ShadcnLock withTheme(LockThemeSelection? value) =>
      value == null ? copyWith(clearTheme: true) : copyWith(theme: value);

  ShadcnLock putLayer(LockLayer layer, LockLayerState state) {
    return copyWith(layers: {...layers, layer: state});
  }

  /// Adds units and files to [layer] without dropping what is already there.
  ShadcnLock mergeLayer(
    LockLayer layer, {
    Set<String> units = const {},
    Map<String, String> files = const {},
  }) {
    final current = layerState(layer);
    return putLayer(
      layer,
      LockLayerState(
        units: lockSortedList([...current.units, ...units]),
        files: {...current.files, ...files},
      ),
    );
  }

  /// Replaces the record for [component], keeping the list sorted by id.
  ShadcnLock upsertComponent(ShadcnLockComponent component) {
    final next =
        components.where((existing) => existing.id != component.id).toList()
          ..add(component)
          ..sort((a, b) => a.id.compareTo(b.id));
    return copyWith(components: next);
  }

  /// Drops [id] from the lock.
  ///
  /// `remove` deletes the component's registry-owned files; its user-owned
  /// files stay on disk unless `--purge-user-themes` is given, which the
  /// caller decides from the dropped record
  /// (`lock.componentFor(id)?.userOwnedPaths`) read before this call.
  ShadcnLock removeComponent(String id) {
    return copyWith(
      components: components.where((component) => component.id != id).toList(),
    );
  }

  ShadcnLockComponent? componentFor(String id) {
    for (final component in components) {
      if (component.id == id) {
        return component;
      }
    }
    return null;
  }

  /// Union with [other]: components are upserted by id, layer units and files
  /// are unioned and [other]'s hashes win because it was written last.
  ShadcnLock mergeWith(ShadcnLock other) {
    var merged = copyWith(
      registry: other.registry.name.isEmpty ? registry : other.registry,
      installRoot: other.installRoot.isEmpty ? installRoot : other.installRoot,
      theme: other.theme ?? theme,
    );
    for (final layer in LockLayer.values) {
      final otherState = other.layerState(layer);
      if (otherState.isEmpty) {
        continue;
      }
      merged = merged.putLayer(layer, layerState(layer).mergeWith(otherState));
    }
    for (final component in other.components) {
      merged = merged.upsertComponent(component);
    }
    return merged;
  }

  Map<String, dynamic> toJson() {
    final sorted = components.toList()..sort((a, b) => a.id.compareTo(b.id));
    return {
      'lockfileVersion': lockfileVersion,
      'registry': registry.toJson(),
      'installRoot': installRoot,
      'theme': theme?.toJson(),
      'layers': {
        for (final layer in LockLayer.values)
          layer.key: layerState(layer).toJson(),
      },
      'components': sorted.map((component) => component.toJson()).toList(),
    };
  }
}
