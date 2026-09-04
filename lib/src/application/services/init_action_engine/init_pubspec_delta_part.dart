part of 'init_action_engine.dart';

class InitPubspecDelta {
  final Map<String, dynamic> dependencies;
  final Map<String, dynamic> devDependencies;
  final List<String> flutterAssets;
  final List<Map<String, dynamic>> flutterFonts;

  const InitPubspecDelta({
    required this.dependencies,
    required this.devDependencies,
    required this.flutterAssets,
    required this.flutterFonts,
  });

  static const empty = InitPubspecDelta(
    dependencies: <String, dynamic>{},
    devDependencies: <String, dynamic>{},
    flutterAssets: <String>[],
    flutterFonts: <Map<String, dynamic>>[],
  );

  bool get isEmpty =>
      dependencies.isEmpty &&
      devDependencies.isEmpty &&
      flutterAssets.isEmpty &&
      flutterFonts.isEmpty;

  InitPubspecDelta merge(InitPubspecDelta other) {
    final mergedDeps = <String, dynamic>{
      ...dependencies,
      ...other.dependencies
    };
    final mergedDev = <String, dynamic>{
      ...devDependencies,
      ...other.devDependencies
    };
    final mergedAssets =
        <String>{...flutterAssets, ...other.flutterAssets}.toList()..sort();
    final mergedFontsByFamily = <String, Map<String, dynamic>>{};
    for (final family in flutterFonts) {
      final key = family['family']?.toString();
      if (key != null && key.isNotEmpty) {
        mergedFontsByFamily[key] = family;
      }
    }
    for (final family in other.flutterFonts) {
      final key = family['family']?.toString();
      if (key != null && key.isNotEmpty) {
        mergedFontsByFamily[key] = family;
      }
    }
    final mergedFonts = mergedFontsByFamily.values.toList()
      ..sort((a, b) => (a['family']?.toString() ?? '')
          .compareTo(b['family']?.toString() ?? ''));

    return InitPubspecDelta(
      dependencies: mergedDeps,
      devDependencies: mergedDev,
      flutterAssets: mergedAssets,
      flutterFonts: mergedFonts,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dependencies': dependencies,
      'devDependencies': devDependencies,
      'flutterAssets': flutterAssets,
      'flutterFonts': flutterFonts,
    };
  }

  factory InitPubspecDelta.fromJson(Map<String, dynamic> json) {
    return InitPubspecDelta(
      dependencies: (json['dependencies'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value),
          ) ??
          const <String, dynamic>{},
      devDependencies: (json['devDependencies'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value),
          ) ??
          const <String, dynamic>{},
      flutterAssets:
          (json['flutterAssets'] as List<dynamic>? ?? const []).cast<String>(),
      flutterFonts: (json['flutterFonts'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((entry) => entry.map(
                (key, value) => MapEntry(key.toString(), value),
              ))
          .toList(),
    );
  }
}
