import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/skill_manager.dart';
import 'package:path/path.dart' as p;

Future<int> runInstallSkillCommand({
  required ArgResults command,
  required String targetDir,
  required String defaultSkillsUrl,
  String? bundledSkillsPath,
  required CliLogger logger,
}) async {
  if (command['help'] == true) {
    print(
      'Usage: flutter_shadcn install-skill [--skill <id>] [--model <name>] [options]',
    );
    print('');
    print(
      '\x1B[33m⚠️  EXPERIMENTAL - This command has not been fully tested yet. Use with caution.\x1B[0m',
    );
    print('');
    print('Modes:');
    print('  (no args)              Multi-skill interactive mode (default)');
    print('  --available, -a        List available skills from registry');
    print('  --list                 List installed skills grouped by model');
    print(
      '  --skill <id>           Install one skill (interactive model choice if --model omitted)',
    );
    print('  --skill <id> --model   Install skill to specific model folder');
    print('  --skills-url           Override skills base URL/path');
    print(
        '  --symlink --model      Symlink one installed skill to other models');
    print(
      '  --uninstall <id>       Remove skill from one model (requires --model)',
    );
    print('  --uninstall-interactive Interactive removal mode');
    return ExitCodes.success;
  }

  final skillsOverride = command['skills-url'] as String?;
  final resolvedSkillsUrl =
      skillsOverride?.isNotEmpty == true ? skillsOverride! : defaultSkillsUrl;
  final skillMgr = SkillManager(
    projectRoot: targetDir,
    skillsBasePath: p.join(targetDir, 'skills'),
    skillsBaseUrl: resolvedSkillsUrl,
    bundledSkillsPath: bundledSkillsPath,
    logger: logger,
  );

  if (command['available'] == true) {
    await skillMgr.listAvailableSkills();
    return ExitCodes.success;
  }
  if (command['list'] == true) {
    await skillMgr.listSkills();
    return ExitCodes.success;
  }
  if (command['uninstall-interactive'] == true) {
    await skillMgr.uninstallSkillsInteractive();
    return ExitCodes.success;
  }
  if (command.wasParsed('uninstall')) {
    final skillId = command['uninstall'] as String;
    final model =
        command.wasParsed('model') ? command['model'] as String? : null;
    if (model == null) {
      logger.error(
        '--uninstall requires --model, or use --uninstall-interactive for menu',
      );
      return ExitCodes.usage;
    }
    await skillMgr.uninstallSkill(skillId: skillId, model: model);
    return ExitCodes.success;
  }
  if (command['symlink'] == true) {
    final skillId =
        command.wasParsed('skill') ? command['skill'] as String : null;
    final targetModel =
        command.wasParsed('model') ? command['model'] as String? : null;
    if (skillId == null || targetModel == null) {
      logger.error('--symlink requires both --skill and --model');
      return ExitCodes.usage;
    }

    final allModels = skillMgr.discoverModelFolders();
    final available = allModels.where((m) => m != targetModel).toList();
    if (available.isEmpty) {
      logger.error('No other models available to symlink to.');
      return ExitCodes.usage;
    }
    logger.section('🔗 Create symlinks for skill: $skillId');
    print('\nAvailable target models:');
    for (var i = 0; i < available.length; i++) {
      print('  ${i + 1}. ${available[i]}');
    }
    print('  ${available.length + 1}. All');
    stdout.write('\nSelect models (comma-separated) or all: ');
    final input = stdin.readLineSync()?.trim() ?? '';
    if (input == '${available.length + 1}' || input.toLowerCase() == 'all') {
      for (final model in available) {
        await skillMgr.symlinkSkill(
          skillId: skillId,
          targetModel: targetModel,
          model: model,
        );
      }
      return ExitCodes.success;
    }

    final indices = input.split(',').map((i) => int.tryParse(i.trim()));
    for (final idx in indices) {
      if (idx != null && idx > 0 && idx <= available.length) {
        await skillMgr.symlinkSkill(
          skillId: skillId,
          targetModel: targetModel,
          model: available[idx - 1],
        );
      }
    }
    return ExitCodes.success;
  }
  if (command.wasParsed('skill')) {
    final skillId = command['skill'] as String;
    final model =
        command.wasParsed('model') ? command['model'] as String? : null;
    if (model != null) {
      await skillMgr.installSkill(skillId: skillId, model: model);
    } else {
      await skillMgr.installSkillInteractive(skillId: skillId);
    }
    return ExitCodes.success;
  }

  await skillMgr.installSkillsInteractive();
  return ExitCodes.success;
}
