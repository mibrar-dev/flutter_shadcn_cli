import 'dart:convert';
import 'dart:io';
import 'package:flutter_shadcn_cli/src/skills/skills_index.dart';
import 'package:path/path.dart' as p;

/// Manages loading of skills.json index for skill discovery.
class SkillsLoader {
  final String skillsBasePath;
  final String? bundledSkillsPath;

  SkillsLoader({
    required this.skillsBasePath,
    this.bundledSkillsPath,
  });

  /// Loads skills.json from the local registry.
  ///
  /// Searches for skills.json in:
  /// 1. {skillsBasePath}/skills.json
  /// 2. {skillsBasePath}/../skills.json
  /// 3. {projectRoot}/shadcn_flutter_kit/flutter_shadcn_kit/skills/skills.json
  Future<SkillsIndex?> load() async {
    final candidates = _findSkillsJsonPaths();

    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) {
        try {
          final content = await file.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          return SkillsIndex.fromJson(json);
        } catch (e) {
          // Try next candidate
          continue;
        }
      }
    }

    return null;
  }

  List<String> _findSkillsJsonPaths() {
    final candidates = <String>[
      if (bundledSkillsPath != null) p.join(bundledSkillsPath!, 'skills.json'),
      p.join(skillsBasePath, 'skills.json'),
      p.join(skillsBasePath, '..', 'skills.json'),
      p.join(skillsBasePath, 'registry', 'skills', 'skills.json'),
    ];

    // Try to find shadcn_flutter_kit
    var current = Directory(skillsBasePath);
    for (var i = 0; i < 5; i++) {
      final kitCandidate = p.join(
        current.path,
        'shadcn_flutter_kit',
        'flutter_shadcn_kit',
        'skills',
        'skills.json',
      );
      candidates.add(kitCandidate);
      candidates.add(p.join(current.path, 'registry', 'skills', 'skills.json'));

      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }

    return candidates;
  }
}
