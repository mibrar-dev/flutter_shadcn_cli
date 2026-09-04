import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;

class InstallerConfigResolver {
  const InstallerConfigResolver({
    required this.registry,
    this.installPathOverride,
    this.sharedPathOverride,
    this.registryNamespace,
  });

  final Registry registry;
  final String? installPathOverride;
  final String? sharedPathOverride;
  final String? registryNamespace;

  String get defaultInstallPath {
    return registry.defaults['installPath'] ?? 'lib/ui/shadcn';
  }

  String get defaultSharedPath {
    return registry.defaults['sharedPath'] ?? 'lib/ui/shadcn/shared';
  }

  String installPath(ShadcnConfig? config) {
    if (installPathOverride != null && installPathOverride!.isNotEmpty) {
      return expandAliases(installPathOverride!, config?.pathAliases);
    }
    final registryEntry = registryNamespace == null
        ? null
        : config?.registryConfig(registryNamespace);
    final override = registryEntry?.installPath ?? config?.installPath;
    if (override != null && override.isNotEmpty) {
      return expandAliases(override, config?.pathAliases);
    }
    return defaultInstallPath;
  }

  String sharedPath(ShadcnConfig? config) {
    if (sharedPathOverride != null && sharedPathOverride!.isNotEmpty) {
      return expandAliases(sharedPathOverride!, config?.pathAliases);
    }
    final registryEntry = registryNamespace == null
        ? null
        : config?.registryConfig(registryNamespace);
    final override = registryEntry?.sharedPath ?? config?.sharedPath;
    if (override != null && override.isNotEmpty) {
      return expandAliases(override, config?.pathAliases);
    }
    return defaultSharedPath;
  }

  String expandAliases(String path, Map<String, String>? aliases) {
    if (aliases == null || aliases.isEmpty) {
      return path;
    }
    if (path.startsWith('@')) {
      final index = path.indexOf('/');
      final name = index == -1 ? path.substring(1) : path.substring(1, index);
      final aliasPath = aliases[name];
      if (aliasPath != null) {
        final suffix = index == -1 ? '' : path.substring(index + 1);
        return suffix.isEmpty ? aliasPath : p.join(aliasPath, suffix);
      }
    }
    return path;
  }
}
