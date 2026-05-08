import 'package:flutter_shadcn_cli/src/registry/file_dependency.dart';

class RegistryFile {
  final String source;
  final String destination;
  final List<FileDependency> dependsOn;
  final String? strategy;

  RegistryFile({
    required this.source,
    required this.destination,
    this.dependsOn = const [],
    this.strategy,
  });

  factory RegistryFile.fromJson(dynamic json) {
    if (json is String) {
      return RegistryFile(source: json, destination: json);
    }
    final map = json as Map<String, dynamic>;
    final deps = (map['dependsOn'] as List<dynamic>? ?? const [])
        .map((e) => FileDependency.fromJson(e))
        .toList();
    return RegistryFile(
      source: map['source'] as String,
      destination: map['destination'] as String,
      dependsOn: deps,
      strategy: map['strategy']?.toString(),
    );
  }
}
