import 'package:flutter_shadcn_cli/src/registry/font_entry.dart';
import 'package:flutter_shadcn_cli/src/registry/platform_entry.dart';
import 'package:flutter_shadcn_cli/src/registry/registry_file.dart';

class ComponentLocaleResource {
  final String locale;
  final String format;
  final String source;
  final String? destinationName;
  final bool required;
  final String? sha256;

  const ComponentLocaleResource({
    required this.locale,
    required this.format,
    required this.source,
    this.destinationName,
    this.required = false,
    this.sha256,
  });

  factory ComponentLocaleResource.fromJson(Map<String, dynamic> json) {
    return ComponentLocaleResource(
      locale: json['locale']?.toString() ?? '',
      format: json['format']?.toString() ?? 'arb',
      source: json['source']?.toString() ?? '',
      destinationName: json['destinationName']?.toString(),
      required: json['required'] == true,
      sha256: json['sha256']?.toString(),
    );
  }

  Map<String, dynamic> toJson({String? destination}) {
    return {
      'locale': locale,
      'format': format,
      'source': source,
      if (destination != null) 'destination': destination,
      if (destinationName != null) 'destinationName': destinationName,
      'required': required,
      if (sha256 != null) 'sha256': sha256,
    };
  }
}

class ComponentLocale {
  final String? defaultLocale;
  final List<String> requiredLocales;
  final List<String> optionalLocales;
  final List<ComponentLocaleResource> resources;

  const ComponentLocale({
    this.defaultLocale,
    this.requiredLocales = const [],
    this.optionalLocales = const [],
    this.resources = const [],
  });

  factory ComponentLocale.fromJson(Map<String, dynamic> json) {
    return ComponentLocale(
      defaultLocale: json['defaultLocale']?.toString(),
      requiredLocales: _stringList(json['required']),
      optionalLocales: _stringList(json['optional']),
      resources: (json['resources'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (entry) => ComponentLocaleResource.fromJson(
              entry.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(),
    );
  }

  bool get hasResources => resources.isNotEmpty;
}

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
  final ComponentLocale? locale;

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
        platform = (json['platform'] as Map<String, dynamic>? ?? const {}).map(
          (key, value) => MapEntry(
            key,
            PlatformEntry.fromJson(value as Map<String, dynamic>),
          ),
        ),
        locale = json['locale'] is Map
            ? ComponentLocale.fromJson(
                (json['locale'] as Map).map(
                  (key, value) => MapEntry(key.toString(), value),
                ),
              )
            : null;
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map((entry) => entry.toString()).toList();
}
