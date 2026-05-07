import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:flutter_shadcn_cli/src/registry_directory.dart';
import 'package:flutter_shadcn_cli/src/resolver_v1.dart';
import 'package:path/path.dart' as p;

class RegistrySource {
  final String namespace;
  final String installRoot;
  final String sharedRoot;
  final RegistryDirectoryEntry? directoryEntry;
  final RegistryConfigEntry? configEntry;

  const RegistrySource({
    required this.namespace,
    required this.installRoot,
    required this.sharedRoot,
    required this.directoryEntry,
    required this.configEntry,
  });

  factory RegistrySource.fromDirectory(RegistryDirectoryEntry entry) {
    return RegistrySource(
      namespace: entry.namespace,
      installRoot: entry.installRoot,
      sharedRoot: '${entry.installRoot}/shared',
      directoryEntry: entry,
      configEntry: null,
    );
  }

  factory RegistrySource.fromConfig({
    required String namespace,
    required RegistryConfigEntry configEntry,
  }) {
    final install = configEntry.installPath ?? 'lib/ui/$namespace';
    final shared = configEntry.sharedPath ?? '$install/shared';
    return RegistrySource(
      namespace: namespace,
      installRoot: install,
      sharedRoot: shared,
      directoryEntry: null,
      configEntry: configEntry,
    );
  }

  Future<Registry> loadRegistry({
    required String projectRoot,
    required bool offline,
    required bool skipIntegrity,
    required CliLogger logger,
    required RegistryDirectoryClient directoryClient,
  }) async {
    if (directoryEntry != null) {
      final content = await directoryClient.loadComponentsJson(
        projectRoot: projectRoot,
        registry: directoryEntry!,
        offline: offline,
        skipIntegrity: skipIntegrity,
        logger: logger,
      );
      final root =
          RegistryLocation.remote(directoryEntry!.baseUrl, offline: offline);
      return Registry.fromContent(
        content: content,
        registryRoot: root,
        sourceRoot: root,
        schemaPath: directoryEntry!.componentsSchemaPath,
        skipIntegrity: skipIntegrity,
        logger: logger,
      );
    }

    final entry = configEntry;
    if (entry == null) {
      throw Exception('Registry source is not configured.');
    }

    final mode = (entry.registryMode ?? '').trim();
    if (mode == 'local' || entry.registryPath != null) {
      final localRoot = resolveLocalPath(projectRoot, entry.registryPath);
      if (localRoot == null) {
        throw Exception(
          'Local registry path is not configured for namespace "$namespace".',
        );
      }
      return Registry.load(
        registryRoot: RegistryLocation.local(localRoot),
        sourceRoot: RegistryLocation.local(p.dirname(localRoot)),
        componentsPath: entry.componentsPath ?? 'components.json',
        schemaPath: entry.componentsSchemaPath,
        trustMode: entry.trustMode,
        trustSha256: entry.trustSha256,
        skipIntegrity: skipIntegrity,
        logger: logger,
      );
    }

    final remoteRoot = entry.baseUrl ?? entry.registryUrl;
    if (remoteRoot == null || remoteRoot.isEmpty) {
      throw Exception(
        'Remote registry URL is not configured for namespace "$namespace".',
      );
    }
    final componentsUri = ResolverV1.resolveUrl(
      remoteRoot,
      entry.componentsPath ?? 'components.json',
    );
    final trustError = RegistryTrustPolicy.validateRemoteRegistryTrust(
      namespace: namespace,
      url: componentsUri,
      trustMode: entry.trustMode,
      trustSha256: entry.trustSha256,
    );
    if (trustError != null) {
      throw Exception(trustError);
    }
    return Registry.load(
      registryRoot: RegistryLocation.remote(remoteRoot, offline: offline),
      sourceRoot: RegistryLocation.remote(remoteRoot, offline: offline),
      componentsPath: entry.componentsPath ?? 'components.json',
      schemaPath: entry.componentsSchemaPath,
      trustMode: entry.trustMode,
      trustSha256: entry.trustSha256,
      skipIntegrity: skipIntegrity,
      cachePath: p.join(
        projectRoot,
        '.shadcn',
        'cache',
        'components_${namespace.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}.json',
      ),
      offline: offline,
      logger: logger,
    );
  }

  static String? resolveLocalPath(String projectRoot, String? path) {
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    final trimmed = path.trim();
    if (p.isAbsolute(trimmed)) {
      return p.normalize(trimmed);
    }
    return p.normalize(p.join(projectRoot, trimmed));
  }
}
