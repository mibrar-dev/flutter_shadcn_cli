import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:path/path.dart' as p;

class InstallerFileSelectionPolicy {
  const InstallerFileSelectionPolicy({
    this.includeFileKindsOverride,
    this.excludeFileKindsOverride,
    this.registryNamespace,
  });

  final Set<String>? includeFileKindsOverride;
  final Set<String>? excludeFileKindsOverride;
  final String? registryNamespace;

  bool shouldInstallFile(String destination, ShadcnConfig? config) {
    final optionalKinds = optionalFileKinds(destination.toLowerCase());
    if (optionalKinds.isEmpty) {
      return true;
    }

    final includeOverride = includeFileKindsOverride ?? const <String>{};
    final excludeOverride = excludeFileKindsOverride ?? const <String>{};
    if (includeOverride.isNotEmpty) {
      return optionalKinds.any(includeOverride.contains);
    }
    if (excludeOverride.isNotEmpty &&
        optionalKinds.any(excludeOverride.contains)) {
      return false;
    }

    final effectiveConfig = config ?? const ShadcnConfig();
    final registryEntry = registryNamespace == null
        ? null
        : effectiveConfig.registryConfig(registryNamespace);

    final includeFromConfig = normalizeFileKinds(
      registryEntry?.includeFiles ??
          effectiveConfig.includeFiles ??
          const <String>[],
    );
    if (includeFromConfig.isNotEmpty) {
      return optionalKinds.any(includeFromConfig.contains);
    }
    final excludeFromConfig = normalizeFileKinds(
      registryEntry?.excludeFiles ??
          effectiveConfig.excludeFiles ??
          const <String>[],
    );
    if (excludeFromConfig.isNotEmpty &&
        optionalKinds.any(excludeFromConfig.contains)) {
      return false;
    }

    if (optionalKinds.contains('readme')) {
      return registryEntry?.includeReadme ??
          effectiveConfig.includeReadme ??
          false;
    }
    if (optionalKinds.contains('meta')) {
      return registryEntry?.includeMeta ?? effectiveConfig.includeMeta ?? true;
    }
    if (optionalKinds.contains('preview')) {
      return registryEntry?.includePreview ??
          effectiveConfig.includePreview ??
          false;
    }
    return true;
  }

  Set<String> optionalFileKinds(String destinationLower) {
    final normalized = destinationLower.replaceAll('\\', '/');
    final base = p.posix.basename(normalized);
    final kinds = <String>{};
    if (base == 'readme.md' || base.contains('readme')) {
      kinds.add('readme');
    }
    if (base == 'meta.json' ||
        base.startsWith('meta.') ||
        base.contains('meta')) {
      kinds.add('meta');
    }
    if (base.contains('preview')) {
      kinds.add('preview');
    }
    return kinds;
  }

  Set<String> normalizeFileKinds(Iterable<String> values) {
    final normalized = <String>{};
    for (final value in values) {
      final token = value.trim().toLowerCase();
      switch (token) {
        case 'readme':
        case 'docs':
          normalized.add('readme');
          break;
        case 'meta':
        case 'metadata':
          normalized.add('meta');
          break;
        case 'preview':
        case 'previews':
          normalized.add('preview');
          break;
      }
    }
    return normalized;
  }
}
