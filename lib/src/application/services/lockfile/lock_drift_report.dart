import 'package:flutter_shadcn_cli/src/application/services/lockfile/lock_json.dart';

/// How a lock-tracked file compares with the bytes on disk.
enum LockFileStatus {
  /// Disk content matches the digest recorded at install time.
  unchanged,

  /// Disk content differs from the recorded digest: locally modified.
  modified,

  /// The file recorded in the lock no longer exists.
  missing;

  static LockFileStatus fromName(String name) {
    return LockFileStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => LockFileStatus.missing,
    );
  }
}

/// One tracked file and its drift verdict.
class LockFileDrift {
  const LockFileDrift({
    required this.path,
    required this.owner,
    required this.status,
    required this.expectedSha,
    this.actualSha,
    this.userOwned = false,
  });

  factory LockFileDrift.fromJson(Map<String, dynamic> json) {
    return LockFileDrift(
      path: normalizeLockPath(json['path']?.toString() ?? ''),
      owner: json['owner']?.toString() ?? '',
      status: LockFileStatus.fromName(json['status']?.toString() ?? ''),
      expectedSha: json['expectedSha256']?.toString() ?? '',
      actualSha: json['actualSha256']?.toString(),
      userOwned: json['userOwned'] == true,
    );
  }

  /// Project relative path.
  final String path;

  /// Component id, or layer key, that recorded the file.
  final String owner;

  final LockFileStatus status;

  /// Digest recorded in the lock.
  final String expectedSha;

  /// Digest of the file on disk; `null` when the file is missing.
  final String? actualSha;

  /// True for `<name>_theme.dart` style files the user may edit freely.
  final bool userOwned;

  bool get isUnchanged => status == LockFileStatus.unchanged;
  bool get isModified => status == LockFileStatus.modified;
  bool get isMissing => status == LockFileStatus.missing;

  /// True when `update` has to say something about this file.
  bool get needsAttention => !isUnchanged;

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'owner': owner,
      'status': status.name,
      'expectedSha256': expectedSha,
      'actualSha256': actualSha,
      'userOwned': userOwned,
    };
  }
}

/// Result of hashing every file the lock tracks.
///
/// User-owned files are reported but never become [updatablePaths]: the CLI
/// must not overwrite or delete a file the user is allowed to edit.
class LockDriftReport {
  const LockDriftReport({
    this.files = const [],
    this.currentManifestSha256,
    this.registryMoved = false,
  });

  final List<LockFileDrift> files;

  /// Digest of the manifest that is on disk right now, when known.
  final String? currentManifestSha256;

  /// True when the registry manifest changed since the install.
  final bool registryMoved;

  List<LockFileDrift> get modified =>
      files.where((file) => file.isModified).toList();

  List<LockFileDrift> get missing =>
      files.where((file) => file.isMissing).toList();

  List<LockFileDrift> get unchanged =>
      files.where((file) => file.isUnchanged).toList();

  /// Modified or missing user-owned files: reported only.
  List<LockFileDrift> get userOwnedDrift =>
      files.where((file) => file.userOwned && file.needsAttention).toList();

  List<LockFileDrift> get registryOwnedDrift =>
      files.where((file) => !file.userOwned && file.needsAttention).toList();

  /// Unchanged, registry-owned paths: the only ones `update` may overwrite.
  Set<String> get updatablePaths => {
        for (final file in files)
          if (file.isUnchanged && !file.userOwned) file.path,
      };

  Set<String> get modifiedPaths => {for (final file in modified) file.path};

  Set<String> get missingPaths => {for (final file in missing) file.path};

  bool get isClean => registryOwnedDrift.isEmpty && !registryMoved;

  bool get hasUserOwnedDrift => userOwnedDrift.isNotEmpty;

  /// Paths grouped by status, for `--json` output.
  Map<String, dynamic> toJson() {
    return {
      'registryMoved': registryMoved,
      'currentManifestSha256': currentManifestSha256,
      'clean': isClean,
      'counts': {
        'total': files.length,
        'unchanged': unchanged.length,
        'modified': modified.length,
        'missing': missing.length,
        'userOwnedDrift': userOwnedDrift.length,
      },
      'files': files.map((file) => file.toJson()).toList(),
    };
  }
}
