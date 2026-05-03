class ResetSnapshotManifest {
  final String projectPath;
  final DateTime createdAtUtc;
  final DateTime expiresAtUtc;
  final List<String> relativePaths;
  final List<String> deletedDirectoryRoots;

  const ResetSnapshotManifest({
    required this.projectPath,
    required this.createdAtUtc,
    required this.expiresAtUtc,
    required this.relativePaths,
    required this.deletedDirectoryRoots,
  });

  factory ResetSnapshotManifest.fromJson(Map<String, dynamic> json) {
    return ResetSnapshotManifest(
      projectPath: json['projectPath']?.toString() ?? '',
      createdAtUtc: DateTime.parse(json['createdAtUtc'].toString()).toUtc(),
      expiresAtUtc: DateTime.parse(json['expiresAtUtc'].toString()).toUtc(),
      relativePaths: (json['relativePaths'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(),
      deletedDirectoryRoots:
          (json['deletedDirectoryRoots'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'projectPath': projectPath,
      'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
      'expiresAtUtc': expiresAtUtc.toUtc().toIso8601String(),
      'relativePaths': relativePaths,
      'deletedDirectoryRoots': deletedDirectoryRoots,
    };
  }
}
