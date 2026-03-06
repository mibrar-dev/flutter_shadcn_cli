import 'package:flutter_shadcn_cli/src/infrastructure/registry_directory/registry_capabilities.dart';
import 'package:flutter_shadcn_cli/src/infrastructure/registry_directory/registry_trust.dart';

class RegistryDirectoryEntry {
  final String id;
  final String displayName;
  final String minCliVersion;
  final String baseUrl;
  final String namespace;
  final String installRoot;
  final Map<String, String> paths;
  final RegistryCapabilities capabilities;
  final RegistryTrust trust;
  final Map<String, dynamic>? init;
  final Map<String, dynamic> raw;

  const RegistryDirectoryEntry({
    required this.id,
    required this.displayName,
    required this.minCliVersion,
    required this.baseUrl,
    required this.namespace,
    required this.installRoot,
    required this.paths,
    required this.capabilities,
    required this.trust,
    required this.init,
    required this.raw,
  });

  factory RegistryDirectoryEntry.fromJson(Map<String, dynamic> json) {
    final install = (json['install'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), value),
        ) ??
        const <String, dynamic>{};
    final paths = (json['paths'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        ) ??
        const <String, String>{};
    return RegistryDirectoryEntry(
      id: json['id']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      minCliVersion: json['minCliVersion']?.toString() ?? '0.0.0',
      baseUrl: json['baseUrl']?.toString() ?? '',
      namespace: install['namespace']?.toString() ?? '',
      installRoot: install['root']?.toString() ?? '',
      paths: paths,
      capabilities: RegistryCapabilities.fromJson(
        (json['capabilities'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      ),
      trust: RegistryTrust.fromJson(
        (json['trust'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      ),
      init: (json['init'] as Map?)?.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      raw: json,
    );
  }

  String get componentsPath => paths['componentsJson'] ?? 'components.json';
  String? get componentsSchemaPath => paths['componentsSchemaJson'];
  String get indexPath => paths['indexJson'] ?? 'index.json';
  String? get indexSchemaPath => paths['indexSchemaJson'];
  String? get themesPath => paths['themesJson'];
  String? get themesSchemaPath => paths['themesSchemaJson'];
  String? get themeConverterDartPath => paths['themeConverterDart'];
  String? get folderStructurePath => paths['folderStructureJson'];
  String? get metaPath => paths['metaJson'];

  bool get hasInlineInit {
    final initMap = init;
    if (initMap == null) {
      return false;
    }
    return initMap['version'] == 1 && initMap['actions'] is List;
  }
}
