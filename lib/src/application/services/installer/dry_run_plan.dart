import 'package:flutter_shadcn_cli/src/registry.dart';

class DryRunPlan {
  final List<String> requested;
  final List<String> missing;
  final List<Component> components;
  final Map<String, List<String>> dependencyGraph;
  final List<String> shared;
  final Map<String, dynamic> pubspecDependencies;
  final List<String> assets;
  final List<FontEntry> fonts;
  final List<String> postInstall;
  final List<String> fileDependencies;
  final Map<String, Set<String>> platformChanges;
  final Map<String, List<Map<String, String>>> componentFiles;
  final Map<String, Map<String, dynamic>> manifestPreview;

  DryRunPlan({
    required this.requested,
    required this.missing,
    required this.components,
    required this.dependencyGraph,
    required this.shared,
    required this.pubspecDependencies,
    required this.assets,
    required this.fonts,
    required this.postInstall,
    required this.fileDependencies,
    required this.platformChanges,
    required this.componentFiles,
    required this.manifestPreview,
  });

  Map<String, dynamic> toJson() {
    return {
      'requested': requested,
      'missing': missing,
      'components': components.map((component) => component.id).toList(),
      'dependencyGraph': dependencyGraph,
      'shared': shared,
      'pubspecDependencies': pubspecDependencies,
      'assets': assets,
      'fonts': fonts
          .map((font) => {
                'family': font.family,
                'fonts': font.fonts
                    .map((entry) => {
                          'asset': entry.asset,
                          'weight': entry.weight,
                          'style': entry.style,
                        })
                    .toList(),
              })
          .toList(),
      'postInstall': postInstall,
      'fileDependencies': fileDependencies,
      'platformChanges': platformChanges.map(
        (key, value) => MapEntry(key, value.toList()..sort()),
      ),
      'componentFiles': componentFiles,
      'manifestPreview': manifestPreview,
    };
  }
}
