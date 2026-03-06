import 'package:flutter_shadcn_cli/src/infrastructure/registry/widget_theme_target_entry.dart';

class WidgetThemeIndexEntry {
  final String componentId;
  final String label;
  final String? defaultTarget;
  final List<WidgetThemeTargetEntry> targets;
  final Map<String, dynamic>? meta;

  const WidgetThemeIndexEntry({
    required this.componentId,
    required this.label,
    required this.targets,
    this.defaultTarget,
    this.meta,
  });

  factory WidgetThemeIndexEntry.fromJson(Map<String, dynamic> json) {
    final rawTargets = json['targets'];
    final targets = rawTargets is List
        ? rawTargets
            .whereType<Map>()
            .map(
              (entry) => WidgetThemeTargetEntry.fromJson(
                entry.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .where((entry) => entry.isValid)
            .toList()
        : const <WidgetThemeTargetEntry>[];
    final componentId =
        json['componentId']?.toString() ?? json['id']?.toString() ?? '';
    final label =
        json['label']?.toString() ?? json['name']?.toString() ?? componentId;
    return WidgetThemeIndexEntry(
      componentId: componentId,
      label: label,
      defaultTarget: json['defaultTarget']?.toString(),
      targets: targets,
      meta: (json['meta'] as Map?)?.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
  }

  bool get isValid => componentId.trim().isNotEmpty;
}
