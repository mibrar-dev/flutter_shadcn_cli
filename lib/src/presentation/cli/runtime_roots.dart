import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

class ResolvedRoots {
  final String? localRegistryRoot;
  final String? cliRoot;

  const ResolvedRoots({
    required this.localRegistryRoot,
    required this.cliRoot,
  });
}

Future<ResolvedRoots> resolveRoots() async {
  final cliRoot = await packageRoot();
  final registryRoot = await resolveRegistryRoot(cliRoot);
  return ResolvedRoots(
    localRegistryRoot: registryRoot,
    cliRoot: cliRoot,
  );
}

Future<String?> resolveRegistryRoot(String? cliRoot) async {
  final envRoot = Platform.environment['SHADCN_REGISTRY_ROOT'];
  if (envRoot != null && envRoot.isNotEmpty) {
    final resolved = validateRegistryRoot(envRoot);
    if (resolved != null) {
      return resolved;
    }
  }

  final kitFromCli = findKitRegistryFromCliRoot(cliRoot);
  if (kitFromCli != null) {
    return kitFromCli;
  }

  final kitFromCwd = findKitRegistryUpwards(Directory.current);
  if (kitFromCwd != null) {
    return kitFromCwd;
  }

  final globalRegistry = globalPackageRegistry();
  if (globalRegistry != null) {
    return globalRegistry;
  }

  if (cliRoot != null) {
    final fromPackage = validateRegistryRoot(p.join(cliRoot, 'registry'));
    if (fromPackage != null) {
      return fromPackage;
    }
  }

  final scriptPath = Platform.script.toFilePath();
  final scriptDir = Directory(p.dirname(scriptPath));
  final kitFromScript = findKitRegistryUpwards(scriptDir);
  if (kitFromScript != null) {
    return kitFromScript;
  }
  final fromScript = findRegistryUpwards(scriptDir);
  if (fromScript != null) {
    return fromScript;
  }

  final fromCwd = findRegistryUpwards(Directory.current);
  if (fromCwd != null) {
    return fromCwd;
  }

  return null;
}

String? findKitRegistryFromCliRoot(String? cliRoot) {
  if (cliRoot == null) {
    return null;
  }
  final parent = p.dirname(cliRoot);
  final candidates = [
    p.join(
      parent,
      'shadcn_flutter_kit',
      'flutter_shadcn_kit',
      'lib',
      'registry',
    ),
    p.join(parent, 'flutter_shadcn_kit', 'lib', 'registry'),
    p.join(parent, 'shadcn_flutter_kit', 'lib', 'registry'),
  ];
  for (final candidate in candidates) {
    final resolved = validateRegistryRoot(candidate);
    if (resolved != null) {
      return resolved;
    }
  }
  return null;
}

String? findKitRegistryUpwards(Directory start) {
  var current = start.absolute;
  for (var i = 0; i < 8; i++) {
    final candidates = [
      p.join(
        current.path,
        'shadcn_flutter_kit',
        'flutter_shadcn_kit',
        'lib',
        'registry',
      ),
      p.join(current.path, 'flutter_shadcn_kit', 'lib', 'registry'),
      p.join(current.path, 'shadcn_flutter_kit', 'lib', 'registry'),
    ];
    for (final candidate in candidates) {
      final resolved = validateRegistryRoot(candidate);
      if (resolved != null) {
        return resolved;
      }
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }
  return null;
}

String? validateRegistryRoot(String candidate) {
  if (File(p.join(candidate, 'components.json')).existsSync()) {
    return candidate;
  }
  if (File(p.join(candidate, 'manifests', 'components.json')).existsSync()) {
    return candidate;
  }
  return null;
}

String? globalPackageRegistry() {
  final pubCache = Platform.environment['PUB_CACHE'] ??
      p.join(Platform.environment['HOME'] ?? '', '.pub-cache');
  if (pubCache.isEmpty) {
    return null;
  }
  final packageRoot = p.join(pubCache, 'global_packages', 'flutter_shadcn_cli');
  return validateRegistryRoot(p.join(packageRoot, 'registry'));
}

Future<String?> packageRoot() async {
  final packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_shadcn_cli/flutter_shadcn_cli.dart'),
  );
  if (packageUri == null) {
    return null;
  }
  final packageLib = File.fromUri(packageUri).parent;
  return packageLib.parent.path;
}

String? findRegistryUpwards(Directory start) {
  var current = start.absolute;
  for (var i = 0; i < 8; i++) {
    final registryDir = Directory(p.join(current.path, 'registry'));
    final componentsFile = File(p.join(registryDir.path, 'components.json'));
    if (componentsFile.existsSync()) {
      return registryDir.path;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }
  return null;
}
