import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/dry_run_plan.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_file_install_part.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/hashing.dart';
import 'package:flutter_shadcn_cli/src/application/services/manifest_closure.dart';
import 'package:path/path.dart' as p;

/// Plans every file of an install: the closure's registry files, the optional
/// component previews and the user-owned theme files.
///
/// Split out of `Installer` so planning stays a pure decision: it reads bytes,
/// compares digests and writes nothing. Sorting is by target so the plan, the
/// human output and the lock all iterate in the same order.
class InstallerFilePlanner {
  const InstallerFilePlanner({
    required this.projectRoot,
    required this.reader,
    required this.installerFiles,
  });

  /// Absolute project root.
  final String projectRoot;

  final RegistryFileReader reader;

  /// Supplies the project-relative target for a registry-relative source.
  final InstallerFileInstaller installerFiles;

  /// Registry-relative preview path of a component. Never declared by the
  /// manifest, so the planner probes for it.
  static String previewFor(String componentId) =>
      'components/$componentId/preview.dart';

  /// Every file the closure touches, with the action the installer would take.
  ///
  /// [userOwnedByComponent] maps a component id to its manifest `userOwned`
  /// list; blocks declare none, so they are simply absent.
  Future<List<PlannedFile>> plan(
    ManifestClosure closure, {
    required bool includePreview,
    required bool overwrite,
    Map<String, List<String>> userOwnedByComponent = const {},
  }) async {
    final planned = <PlannedFile>[];
    final registryFiles = <String>{...closure.files};
    if (includePreview) {
      for (final id in closure.components) {
        final preview = previewFor(id);
        if (await reader.readBytes(preview) != null) {
          registryFiles.add(preview);
        }
      }
    }
    final sources = registryFiles.toList()..sort();
    for (final source in sources) {
      planned.add(
        await _decideFile(
          source: source,
          target: installerFiles.targetPathFor(source),
          userOwned: false,
          overwrite: overwrite,
        ),
      );
    }
    for (final entry in userOwnedByComponent.entries) {
      for (final source in entry.value) {
        planned.add(
          await _decideFile(
            source: source,
            target: installerFiles.targetPathFor(source),
            userOwned: true,
            overwrite: false,
          ),
        );
      }
    }
    planned.sort((a, b) => a.target.compareTo(b.target));
    return planned;
  }

  /// Decides one file: add when the destination is absent, keep when it is
  /// user-owned, skip when the bytes are identical or locally modified, and
  /// update only when the caller allowed overwrites.
  Future<PlannedFile> _decideFile({
    required String source,
    required String target,
    required bool userOwned,
    required bool overwrite,
  }) async {
    final sourceBytes = await reader.readBytes(source);
    if (sourceBytes == null) {
      throw RegistryFileMissingException(source);
    }
    final sourceSha = FileHashing.ofBytes(sourceBytes);
    final destination = File(p.join(projectRoot, target));
    if (!await destination.exists()) {
      return PlannedFile(
        source: source,
        target: target,
        action: PlanAction.add,
        userOwned: userOwned,
        sha256: sourceSha,
      );
    }
    final destinationSha = FileHashing.ofBytes(await destination.readAsBytes());
    if (userOwned) {
      return PlannedFile(
        source: source,
        target: target,
        action: PlanAction.keep,
        userOwned: true,
        reason: 'user-owned',
        sha256: destinationSha,
      );
    }
    if (destinationSha == sourceSha) {
      return PlannedFile(
        source: source,
        target: target,
        action: PlanAction.skip,
        reason: 'identical',
        sha256: sourceSha,
      );
    }
    if (overwrite) {
      return PlannedFile(
        source: source,
        target: target,
        action: PlanAction.update,
        reason: 'overwrite',
        sha256: sourceSha,
      );
    }
    return PlannedFile(
      source: source,
      target: target,
      action: PlanAction.skip,
      reason: 'locally modified',
      sha256: sourceSha,
    );
  }
}
