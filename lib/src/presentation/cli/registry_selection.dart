import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/arg_helpers.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/runtime_roots.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;

class RegistrySelection {
  final String mode;
  final String? namespace;
  final RegistryLocation registryRoot;
  final RegistryLocation sourceRoot;
  final String componentsPath;
  final String? schemaPath;
  final String indexPath;
  final String? indexSchemaPath;
  final String? themesPath;
  final String? themesSchemaPath;
  final bool? capabilitySharedGroups;
  final bool? capabilityComposites;
  final bool? capabilityTheme;
  final String? trustMode;
  final String? trustSha256;

  const RegistrySelection({
    required this.mode,
    required this.namespace,
    required this.registryRoot,
    required this.sourceRoot,
    this.componentsPath = 'components.json',
    this.schemaPath,
    this.indexPath = 'index.json',
    this.indexSchemaPath,
    this.themesPath,
    this.themesSchemaPath,
    this.capabilitySharedGroups,
    this.capabilityComposites,
    this.capabilityTheme,
    this.trustMode,
    this.trustSha256,
  });
}

RegistrySelection resolveRegistrySelection(
  ArgResults? args,
  ResolvedRoots roots,
  ShadcnConfig config,
  bool offline, {
  String? namespaceOverride,
}) {
  final selectedNamespace = namespaceOverride ??
      optionalStringOption(args, 'registry-name')?.trim() ??
      config.effectiveDefaultNamespace;
  final selectedEntry = config.registryConfig(selectedNamespace);
  if (selectedEntry == null &&
      (optionalStringOption(args, 'registry-name')?.trim().isNotEmpty == true ||
          config.hasRegistries)) {
    stderr.writeln('Error: Registry namespace "$selectedNamespace" not found.');
    exit(ExitCodes.configInvalid);
  }

  final explicitPathOverride = optionalStringOption(args, 'registry-path');
  final explicitUrlOverride = optionalStringOption(args, 'registry-url');
  final mode = explicitPathOverride?.trim().isNotEmpty == true
      ? 'local'
      : explicitUrlOverride?.trim().isNotEmpty == true
          ? 'remote'
          : optionalStringOption(args, 'registry') ??
              selectedEntry?.registryMode ??
              config.registryMode ??
              'auto';
  final pathOverride = explicitPathOverride ??
      selectedEntry?.registryPath ??
      config.registryPath;
  final urlOverride = explicitUrlOverride ??
      selectedEntry?.baseUrl ??
      selectedEntry?.registryUrl ??
      config.registryUrl;
  final componentsPath = selectedEntry?.componentsPath ?? 'components.json';
  final schemaPath = selectedEntry?.componentsSchemaPath;
  final indexPath = selectedEntry?.indexPath ?? 'index.json';
  final indexSchemaPath = selectedEntry?.indexSchemaPath;
  final themesPath = selectedEntry?.themesPath;
  final themesSchemaPath = selectedEntry?.themesSchemaPath;
  final capabilitySharedGroups = selectedEntry?.capabilitySharedGroups;
  final capabilityComposites = selectedEntry?.capabilityComposites;
  final capabilityTheme = selectedEntry?.capabilityTheme;
  final trustMode = selectedEntry?.trustMode;
  final trustSha256 = selectedEntry?.trustSha256;

  if (mode == 'local' || mode == 'auto') {
    var localRoot = resolveLocalRoot(
      pathOverride,
      roots.localRegistryRoot,
      config.registryPath,
    );
    localRoot ??= findKitRegistryUpwards(Directory.current);
    localRoot ??= findKitRegistryFromCliRoot(roots.cliRoot);
    if (localRoot != null) {
      final sourceRoot = p.dirname(localRoot);
      return RegistrySelection(
        mode: 'local',
        namespace: selectedNamespace,
        registryRoot: RegistryLocation.local(localRoot, offline: offline),
        sourceRoot: RegistryLocation.local(sourceRoot, offline: offline),
        componentsPath: componentsPath,
        schemaPath: schemaPath,
        indexPath: indexPath,
        indexSchemaPath: indexSchemaPath,
        themesPath: themesPath,
        themesSchemaPath: themesSchemaPath,
        capabilitySharedGroups: capabilitySharedGroups,
        capabilityComposites: capabilityComposites,
        capabilityTheme: capabilityTheme,
        trustMode: trustMode,
        trustSha256: trustSha256,
      );
    }
    if (mode == 'local') {
      stderr.writeln('Error: Local registry not found.');
      stderr.writeln('Set SHADCN_REGISTRY_ROOT or --registry-path.');
      exit(ExitCodes.registryNotFound);
    }
  }

  final remoteBase = resolveRemoteBase(urlOverride);
  if (selectedEntry != null &&
      (selectedEntry.baseUrl != null || selectedEntry.componentsPath != null)) {
    return RegistrySelection(
      mode: 'remote',
      namespace: selectedNamespace,
      registryRoot: RegistryLocation.remote(remoteBase, offline: offline),
      sourceRoot: RegistryLocation.remote(remoteBase, offline: offline),
      componentsPath: componentsPath,
      schemaPath: schemaPath,
      indexPath: indexPath,
      indexSchemaPath: indexSchemaPath,
      themesPath: themesPath,
      themesSchemaPath: themesSchemaPath,
      capabilitySharedGroups: capabilitySharedGroups,
      capabilityComposites: capabilityComposites,
      capabilityTheme: capabilityTheme,
      trustMode: trustMode,
      trustSha256: trustSha256,
    );
  }
  final remoteRoots = _resolveRemoteRoots(remoteBase);
  return RegistrySelection(
    mode: 'remote',
    namespace: selectedNamespace,
    registryRoot:
        RegistryLocation.remote(remoteRoots.registryRoot, offline: offline),
    sourceRoot:
        RegistryLocation.remote(remoteRoots.sourceRoot, offline: offline),
    componentsPath: componentsPath,
    schemaPath: schemaPath,
    indexPath: indexPath,
    indexSchemaPath: indexSchemaPath,
    themesPath: themesPath,
    themesSchemaPath: themesSchemaPath,
    capabilitySharedGroups: capabilitySharedGroups,
    capabilityComposites: capabilityComposites,
    capabilityTheme: capabilityTheme,
    trustMode: trustMode,
    trustSha256: trustSha256,
  );
}

String? resolveLocalRoot(
  String? override,
  String? detected,
  String? configPath,
) {
  if (override != null && override.isNotEmpty) {
    return validateRegistryRoot(override);
  }
  if (configPath != null && configPath.isNotEmpty) {
    return validateRegistryRoot(configPath) ?? detected;
  }
  return detected;
}

String resolveRemoteBase(String? override) {
  final envUrl = Platform.environment['SHADCN_REGISTRY_URL'];
  if (override != null && override.isNotEmpty) {
    return override;
  }
  if (envUrl != null && envUrl.isNotEmpty) {
    return envUrl;
  }
  return defaultRemoteRegistryBase;
}

({String registryRoot, String sourceRoot}) _resolveRemoteRoots(String base) {
  final normalized =
      base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  if (normalized.endsWith('/registry')) {
    final sourceRoot =
        normalized.substring(0, normalized.length - '/registry'.length);
    return (registryRoot: normalized, sourceRoot: sourceRoot);
  }
  return (
    registryRoot: '$normalized/registry',
    sourceRoot: normalized,
  );
}

String? componentsJsonCachePath(RegistryLocation registryRoot) {
  if (!registryRoot.isRemote) {
    return null;
  }
  final home = Platform.environment['HOME'] ?? '';
  if (home.isEmpty) {
    return null;
  }
  final cacheRoot = p.join(home, '.flutter_shadcn', 'cache', 'registry');
  final safeKey = sanitizeCacheKey(registryRoot.root);
  return p.join(cacheRoot, safeKey, 'components.json');
}

Future<String> readComponentsJson(
  RegistrySelection selection, {
  required bool offline,
}) async {
  if (offline && selection.registryRoot.isRemote) {
    final cachePath = componentsJsonCachePath(selection.registryRoot);
    if (cachePath == null) {
      throw Exception('Offline mode: cache path not available.');
    }
    final cacheFile = File(cachePath);
    if (!await cacheFile.exists()) {
      throw Exception('Offline mode: cached components.json not found.');
    }
    return cacheFile.readAsString();
  }
  return selection.registryRoot.readString(selection.componentsPath);
}

String sanitizeCacheKey(String value) {
  final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (safe.length > 80) {
    return safe.substring(0, 80);
  }
  return safe;
}

const String defaultRemoteRegistryBase =
    'https://cdn.jsdelivr.net/gh/ibrar-x/shadcn_flutter_kit@latest/flutter_shadcn_kit/lib';
