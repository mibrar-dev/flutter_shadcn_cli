import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/lockfile/hashing.dart';
import 'package:path/path.dart' as p;

/// Reads registry source files by their registry-relative path.
///
/// The bundled/local registry reads from a directory; a remote registry
/// (plan §9.5) supplies an HTTP-backed implementation. The installer core only
/// depends on this interface so tests never touch the network.
abstract class RegistryFileReader {
  /// Raw bytes of [relPath], or `null` when the registry does not have it.
  Future<List<int>?> readBytes(String relPath);

  /// UTF-8 text of [relPath], or `null` when missing.
  Future<String?> readString(String relPath);
}

/// [RegistryFileReader] over a local registry checkout.
class DirectoryRegistryFileReader implements RegistryFileReader {
  const DirectoryRegistryFileReader(this.root);

  /// Absolute registry root (the directory holding foundation/, theme/, ...).
  final String root;

  @override
  Future<List<int>?> readBytes(String relPath) async {
    final file = File(p.join(root, p.normalize(relPath)));
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  @override
  Future<String?> readString(String relPath) async {
    final bytes = await readBytes(relPath);
    return bytes == null ? null : decodeRegistryText(bytes);
  }
}

/// Decodes registry Dart source; malformed UTF-8 is replaced rather than fatal.
String decodeRegistryText(List<int> bytes) =>
    utf8.decode(bytes, allowMalformed: true);

/// A manifest-declared file is missing from the registry source.
class RegistryFileMissingException implements Exception {
  const RegistryFileMissingException(this.relPath);

  final String relPath;

  @override
  String toString() =>
      'Registry file "$relPath" is declared by the manifest but missing from '
      'the registry source.';
}

/// A relative import would resolve outside the install layout.
///
/// Verbatim copying is only safe while every registry file keeps its depth
/// (plan §3); an import like `../../../foundation/x.dart` would escape the
/// install root once copied, so the install aborts before writing anything.
class ImportGuardException implements Exception {
  const ImportGuardException({
    required this.file,
    required this.importTarget,
    required this.resolved,
  });

  final String file;
  final String importTarget;
  final String resolved;

  @override
  String toString() =>
      'Import guard: "$file" imports "$importTarget" which resolves to '
      '"$resolved" outside foundation/, theme/, primitives/, components/ or '
      'blocks/.';
}

/// A file the installer wrote.
class InstalledFile {
  const InstalledFile({
    required this.source,
    required this.target,
    required this.sha256,
  });

  /// Registry-relative source path.
  final String source;

  /// Project-relative destination path.
  final String target;

  /// sha256 of the bytes written.
  final String sha256;
}

/// Copies registry files verbatim into the depth-preserving install layout.
///
/// The only transformations are: pick the destination from the registry-relative
/// path, and reject relative imports that would escape the layout. No import
/// rewriting (plan §3).
class InstallerFileInstaller {
  const InstallerFileInstaller({
    required this.projectRoot,
    required this.installRoot,
    required this.reader,
  });

  /// Absolute project root.
  final String projectRoot;

  /// Project-relative install root, e.g. `lib/ui/shadcn`.
  final String installRoot;

  final RegistryFileReader reader;

  /// Layer directories, kept at the same depth as in the registry.
  static const List<String> layerDirs = ['foundation', 'theme', 'primitives'];

  /// Component directory name.
  static const String componentsDir = 'components';

  /// Block directory name (registry layer 4, P6-B1).
  static const String blocksDir = 'blocks';

  static final RegExp _importPattern = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );

  /// Project-relative destination for [relPath].
  ///
  /// `foundation/x.dart` -> `<root>/foundation/x.dart`;
  /// `components/button/button.dart` -> `<root>/components/button/button.dart`;
  /// `blocks/login-01/login_01.dart` -> `<root>/blocks/login-01/login_01.dart`.
  /// `themes/*.json`, block `docs` and other non-copyable paths are rejected.
  String targetPathFor(String relPath) {
    final normalized = p.posix.normalize(relPath.replaceAll('\\', '/'));
    final head = normalized.split('/').first;
    if (head == componentsDir ||
        head == blocksDir ||
        layerDirs.contains(head)) {
      return p.posix.join(installRoot, normalized);
    }
    throw ArgumentError.value(
      relPath,
      'relPath',
      'not a copyable registry path',
    );
  }

  /// Reads every [relPath]; throws [RegistryFileMissingException] for a gap.
  Future<Map<String, List<int>>> readAll(Iterable<String> relPaths) async {
    final result = <String, List<int>>{};
    for (final relPath in relPaths) {
      final bytes = await reader.readBytes(relPath);
      if (bytes == null) {
        throw RegistryFileMissingException(relPath);
      }
      result[relPath] = bytes;
    }
    return result;
  }

  /// Scans every relative `import`/`export` and throws [ImportGuardException]
  /// for the first one that would escape the layout.
  ///
  /// [contents] is keyed by registry-relative path. `dart:` and `package:`
  /// imports are ignored; a simple line scan is enough (plan §9.8).
  void assertImportGuard(Map<String, String> contents) {
    final files = contents.keys.toList()..sort();
    for (final file in files) {
      final baseDir = p.posix.dirname(file.replaceAll('\\', '/'));
      for (final match in _importPattern.allMatches(contents[file]!)) {
        final importTarget = match.group(1)!;
        if (importTarget.isEmpty ||
            importTarget.startsWith('dart:') ||
            importTarget.startsWith('package:')) {
          continue;
        }
        final resolved = p.posix.normalize(p.posix.join(baseDir, importTarget));
        final escapes = resolved == '..' ||
            resolved.startsWith('../') ||
            p.posix.isAbsolute(resolved);
        final head = resolved.split('/').first;
        final insideLayout = head == componentsDir ||
            head == blocksDir ||
            layerDirs.contains(head);
        if (escapes || !insideLayout) {
          throw ImportGuardException(
            file: file,
            importTarget: importTarget,
            resolved: resolved,
          );
        }
      }
    }
  }

  /// Writes [bytes] to [target] (project-relative), creating parents.
  Future<InstalledFile> write({
    required String source,
    required String target,
    required List<int> bytes,
  }) async {
    final absolute = _resolve(target);
    final file = File(absolute);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return InstalledFile(
      source: source,
      target: target,
      sha256: FileHashing.ofBytes(bytes),
    );
  }

  /// Absolute path of a project-relative [target], rejected when it escapes.
  String _resolve(String target) {
    final rootAbs = p.normalize(p.absolute(projectRoot));
    final absolute = p.normalize(p.join(rootAbs, target));
    if (absolute != rootAbs && !p.isWithin(rootAbs, absolute)) {
      throw ArgumentError.value(target, 'target', 'escapes the project root');
    }
    return absolute;
  }
}
