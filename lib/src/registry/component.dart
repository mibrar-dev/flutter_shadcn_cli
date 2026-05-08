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
  final List<String> manifestKeys;
  final List<String> postInstallNamespaces;
  final List<String> localeNamespaces;
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
        postInstall = List<String>.from(json['postInstall'] ?? []),
        manifestKeys = _stringList(json['manifestKeys']),
        postInstallNamespaces = _stringList(json['postInstallNamespaces']),
        localeNamespaces = _stringList(json['localeNamespaces']),
        platform = (json['platform'] as Map<String, dynamic>? ?? const {})
            .map((key, value) => MapEntry(
                  key,
                  PlatformEntry.fromJson(value as Map<String, dynamic>),
                ));
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map((entry) => entry.toString()).toList();
}
