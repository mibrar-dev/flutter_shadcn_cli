import 'package:flutter_shadcn_cli/src/registry/font_entry.dart';
import 'package:flutter_shadcn_cli/src/registry/platform_entry.dart';
import 'package:flutter_shadcn_cli/src/registry/registry_file.dart';

class Component {
  final String id;
  final String name;
  final String? category;
  final String? version;
  final List<String> tags;
  final List<RegistryFile> files;
  final List<String> shared;
  final List<String> dependsOn;
  final List<String> assets;
  final List<FontEntry> fonts;
  final Map<String, dynamic> pubspec;
  final List<String> postInstall;
  final bool postInstallRequiredManualSteps;
  final Map<String, PlatformEntry> platform;

  Component.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        name = json['name'],
        category = json['category'] as String?,
        version = json['version'] as String?,
        tags = List<String>.from(json['tags'] ?? const []),
        files = (json['files'] as List)
            .map((e) => RegistryFile.fromJson(e))
            .toList(),
        shared = List<String>.from(json['shared'] ?? []),
        dependsOn = List<String>.from(json['dependsOn'] ?? []),
        assets = List<String>.from(json['assets'] ?? []),
        fonts = (json['fonts'] as List<dynamic>? ?? const [])
            .map((e) => FontEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        pubspec = json['pubspec'] ?? {},
        postInstall = _parsePostInstallNotes(json['postInstall']),
        postInstallRequiredManualSteps =
            _parsePostInstallRequiredManualSteps(json['postInstall']),
        platform = (json['platform'] as Map<String, dynamic>? ?? const {})
            .map((key, value) => MapEntry(
                  key,
                  PlatformEntry.fromJson(value as Map<String, dynamic>),
                ));
}

List<String> _parsePostInstallNotes(Object? value) {
  if (value == null) {
    return const [];
  }
  if (value is List) {
    return value.map((entry) => entry.toString()).toList();
  }
  if (value is Map<String, dynamic>) {
    final notes = value['notes'];
    final parsedNotes = notes is List
        ? notes.map((entry) => entry.toString()).toList()
        : <String>[];
    final requiredManualSteps = value['requiredManualSteps'] == true;
    if (requiredManualSteps && parsedNotes.isEmpty) {
      throw const FormatException(
        'postInstall.requiredManualSteps requires at least one note.',
      );
    }
    return parsedNotes;
  }
  throw const FormatException(
    'postInstall must be a list of notes or an object with notes.',
  );
}

bool _parsePostInstallRequiredManualSteps(Object? value) {
  if (value is Map<String, dynamic>) {
    return value['requiredManualSteps'] == true;
  }
  return false;
}
