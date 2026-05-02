import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/skills_loader.dart';
import 'package:flutter_shadcn_cli/src/skills/skill_entry.dart';

/// AI model folder to display name mapping.
const Map<String, String> aiModelDisplayNames = {
  '.claude': 'Claude (Anthropic)',
  '.cline': 'Cline',
  '.codebuddy': 'CodeBuddy',
  '.codex': 'Codex (OpenAI)',
  '.commandcode': 'CommandCode',
  '.continue': 'Continue',
  '.crush': 'Crush',
  '.cursor': 'Cursor',
  '.factory': 'Factory',
  '.gemini': 'Gemini (Google)',
  '.goose': 'Goose',
  '.gpt4': 'GPT-4 (OpenAI)',
  '.junie': 'Junie',
  '.kilocode': 'KiloCode',
  '.kiro': 'Kiro',
  '.kode': 'Kode',
  '.mcpjam': 'MCPJam',
  '.mux': 'Mux',
  '.neovate': 'Neovate',
  '.opencode': 'OpenCode',
  '.openhands': 'OpenHands',
  '.pi': 'Pi',
  '.pochi': 'Pochi',
  '.qoder': 'Qoder',
  '.qwen': 'Qwen',
  '.roo': 'Roo',
  '.trae': 'Trae',
  '.windsurf': 'Windsurf',
  '.zencoder': 'ZenCoder',
};

/// Manages AI skill installation and management.
///
/// Skills are downloaded from GitHub and installed into AI model directories.
/// Supports:
/// - Interactive model selection from .{modelName}/ folders
/// - Install to all models (creates separate copies)
/// - Install to selected model
/// - Create symlinks for all models (if skill installed to one)
class SkillManager {
  final String projectRoot;
  final String skillsBasePath;
  final String skillsBaseUrl;
  final String? bundledSkillsPath;
  final CliLogger logger;

  SkillManager({
    required this.projectRoot,
    required this.skillsBasePath,
    String? skillsBaseUrl,
    this.bundledSkillsPath,
    required this.logger,
  }) : skillsBaseUrl = skillsBaseUrl?.isNotEmpty == true
            ? skillsBaseUrl!
            : 'https://raw.githubusercontent.com/ibrar-x/shadcn_flutter_kit/main/flutter_shadcn_kit/skills';

  /// Installs a skill from GitHub.
  ///
  /// Can install for a specific AI model or as a shared skill (symlink).
  ///
  /// [skillId]: Name of the skill folder to install
  /// [model]: Optional AI model name (e.g., 'gpt-4', 'claude'). If provided, installs
  ///          to skillsPath/models/{model}/. If null, installs to shared skillsPath/
  Future<void> installSkill({
    required String skillId,
    String? model,
  }) async {
    logger.section('🎯 Installing Skill: $skillId');

    if (skillId.isEmpty) {
      logger.error('Please provide a skill id.');
      throw Exception('Skill id cannot be empty');
    }

    // Determine installation path
    final installPath = _getInstallPath(skillId, model);
    final skillDir = Directory(installPath);

    try {
      // Create target directory
      if (!skillDir.existsSync()) {
        skillDir.createSync(recursive: true);
        logger.detail('Created skill directory: $installPath');
      }

      // Download skill files
      logger.detail('Downloading skill from $skillsBaseUrl/$skillId');
      await _downloadSkillFiles(skillId, installPath);

      if (model != null) {
        logger.success('✓ Skill "$skillId" installed for model: $model');
      } else {
        logger.success('✓ Skill "$skillId" installed (shared)');
      }
    } catch (e) {
      logger.error('Failed to install skill: $e');
      rethrow;
    }
  }

  /// Symlinks a shared skill to a model-specific directory.
  ///
  /// Useful for sharing a skill across multiple models without duplicating files.
  /// Creates symlinks from a source model to target models.
  ///
  /// The source model must have the skill installed. Target models will have
  /// symlinks pointing to the source skill folder.
  ///
  /// [skillId]: The skill to symlink
  /// [targetModel]: The model where the skill is installed (source)
  /// [model]: The model to create symlink in (destination)
  Future<void> symlinkSkill({
    required String skillId,
    required String targetModel,
    required String model,
  }) async {
    logger.section('🔗 Symlinking Skill: $skillId');

    try {
      final sourcePath = p.join(projectRoot, targetModel, 'skills', skillId);
      final targetPath = p.join(projectRoot, model, 'skills', skillId);

      final sourceDir = Directory(sourcePath);
      if (!sourceDir.existsSync()) {
        logger.error(
          'Skill "$skillId" not found in $targetModel. Install it first.',
        );
        throw Exception('Skill not found in source model: $skillId');
      }

      // Create parent directory if needed
      final parentDir = Directory(p.dirname(targetPath));
      if (!parentDir.existsSync()) {
        parentDir.createSync(recursive: true);
      }

      // Create symlink
      final link = Link(targetPath);
      if (await link.exists()) {
        logger.info('Symlink already exists: $targetPath');
        return;
      }

      await link.create(sourcePath, recursive: true);
      logger.success('✓ Symlinked "$skillId" from $targetModel -> $model');
    } catch (e) {
      logger.error('Failed to symlink skill: $e');
      rethrow;
    }
  }

  /// Lists installed skills.
  ///
  /// Shows shared skills and per-model installations.
  Future<void> listSkills() async {
    logger
        .warn('⚠️  EXPERIMENTAL: This feature has not been fully tested yet.');
    logger.section('📚 Installed Skills');

    final shared = <String>[];
    final models = <String, List<String>>{};

    final sharedDir = Directory(skillsBasePath);
    if (sharedDir.existsSync()) {
      for (final entity in sharedDir.listSync()) {
        if (entity is Directory) {
          shared.add(p.basename(entity.path));
        }
      }
    }

    final modelFolders = discoverModelFolders();
    for (final model in modelFolders) {
      final modelSkillsDir = Directory(p.join(projectRoot, model, 'skills'));
      if (!modelSkillsDir.existsSync()) {
        continue;
      }

      final skillIds = <String>[];
      for (final skillEntity in modelSkillsDir.listSync()) {
        if (skillEntity is Directory || skillEntity is Link) {
          skillIds.add(p.basename(skillEntity.path));
        }
      }

      if (skillIds.isNotEmpty) {
        models[model] = skillIds;
      }
    }

    if (shared.isNotEmpty) {
      print('\n  \x1B[1m📚 Shared Skills:\x1B[0m');
      for (final skill in shared) {
        print('    \x1B[36m●\x1B[0m $skill');
      }
    }

    if (models.isNotEmpty) {
      print('\n  \x1B[1m🤖 Model-Specific Skills:\x1B[0m');
      for (final model in models.keys) {
        final displayName = aiModelDisplayNames[model] ?? model;
        print('    \x1B[35m▸\x1B[0m \x1B[1m$displayName\x1B[0m');
        for (final skill in models[model]!) {
          print('      \x1B[90m─\x1B[0m $skill');
        }
      }
    }

    if (shared.isEmpty && models.isEmpty) {
      logger.info('No skills installed.');
    }
  }

  /// Uninstalls a skill or model-specific skill.
  Future<void> uninstallSkill({
    required String skillId,
    String? model,
  }) async {
    final uninstallPath = _getInstallPath(skillId, model);

    // Check if it's a symlink first
    final link = Link(uninstallPath);
    final directory = Directory(uninstallPath);

    // Skip if doesn't exist (might be in a removed folder)
    if (!link.existsSync() && !directory.existsSync()) {
      logger.warn('⚠️  Skill not found: $uninstallPath (skipping)');
      return;
    }

    try {
      if (link.existsSync()) {
        // It's a symlink - resolve BEFORE deleting
        String targetPath = '';
        try {
          targetPath = await link.resolveSymbolicLinks();
        } catch (_) {
          // Broken symlink - just delete it
          targetPath = '';
        }

        await link.delete();

        final displayType = targetPath.isNotEmpty
            ? 'symlink (to ${p.basename(targetPath)})'
            : 'symlink';
        if (model != null) {
          logger.success('✓ Removed $displayType "$skillId" for model: $model');
        } else {
          logger.success('✓ Removed shared $displayType: $skillId');
        }
      } else if (directory.existsSync()) {
        // It's a real directory - delete it recursively
        await directory.delete(recursive: true);
        if (model != null) {
          logger.success('✓ Uninstalled "$skillId" for model: $model');
        } else {
          logger.success('✓ Uninstalled shared skill: $skillId');
        }
      }
    } catch (e) {
      logger.error('Failed to uninstall skill: $e');
      rethrow;
    }
  }

  /// Gets the installation path for a skill.
  ///
  /// Returns `{projectRoot}/{model}/skills/{skillId}` for model-specific installation.
  String _getInstallPath(String skillId, String? model) {
    if (model != null) {
      return p.join(projectRoot, model, 'skills', skillId);
    }
    // Fallback for shared skills (not typically used with AI models)
    return p.join(skillsBasePath, skillId);
  }

  /// Discovers all AI model folders in the project root.
  ///
  /// Returns a list of folder names starting with '.' (e.g., .claude, .gpt4, .cursor).
  /// Only returns folders that actually exist or offers to create them interactively.
  List<String> discoverModelFolders() {
    try {
      final projectDir = Directory(projectRoot);
      if (!projectDir.existsSync()) {
        return [];
      }

      final existing = _listHiddenDirs(projectRoot);
      if (existing.isNotEmpty) {
        return existing;
      }

      // Auto-create the default model folders when none exist.
      final defaults = _getKnownAIModels();
      for (final model in defaults) {
        final dir = Directory(p.join(projectRoot, model));
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
      }
      return defaults;
    } catch (e) {
      logger.error('Error discovering model folders: $e');
      return [];
    }
  }

  /// Returns the hardcoded list of known AI model folders.
  List<String> _getKnownAIModels() {
    return const [
      '.claude',
      '.cline',
      '.codebuddy',
      '.codex',
      '.commandcode',
      '.continue',
      '.crush',
      '.cursor',
      '.factory',
      '.gemini',
      '.goose',
      '.gpt4',
      '.junie',
      '.kilocode',
      '.kiro',
      '.kode',
      '.mcpjam',
      '.mux',
      '.neovate',
      '.opencode',
      '.openhands',
      '.pi',
      '.pochi',
      '.qoder',
      '.qwen',
      '.roo',
      '.trae',
      '.windsurf',
      '.zencoder',
    ];
  }

  List<String> _listHiddenDirs(String rootPath) {
    final rootDir = Directory(rootPath);
    if (!rootDir.existsSync()) {
      return [];
    }

    // Get the list of known AI model folders (from constants, not recursively)
    final knownModels = _getKnownAIModels().toSet();

    final models = <String>[];
    for (final entity in rootDir.listSync()) {
      if (entity is Directory) {
        final name = p.basename(entity.path);
        // Only include folders that are in the known AI models list
        if (knownModels.contains(name)) {
          models.add(name);
        }
      }
    }

    return models..sort();
  }

  /// Lists available skills from skills.json index.
  Future<void> listAvailableSkills() async {
    logger
        .warn('⚠️  EXPERIMENTAL: This feature has not been fully tested yet.');
    logger.section('📚 Available Skills');

    final loader = SkillsLoader(
      skillsBasePath: skillsBasePath,
      bundledSkillsPath: bundledSkillsPath,
    );
    final index = await loader.load();

    if (index == null || index.skills.isEmpty) {
      logger.info('No skills found in registry.');
      logger.detail('Skills index: skills.json');
      return;
    }

    print('');
    for (var i = 0; i < index.skills.length; i++) {
      final skill = index.skills[i];
      print(
          '  \x1B[36m${i + 1}.\x1B[0m \x1B[1m${skill.name}\x1B[0m \x1B[90m(${skill.id})\x1B[0m');
      print('     \x1B[90m${skill.description}\x1B[0m');
      print(
          '     \x1B[35m📌 Version: ${skill.version}\x1B[0m \x1B[90m|\x1B[0m \x1B[33m⚡ Status: ${skill.status}\x1B[0m');
      if (i < index.skills.length - 1) print('');
    }
    print('');
    logger.info('${index.skills.length} skills available.');
  }

  /// Interactive multi-skill installation flow.
  ///
  /// Shows available skills from skills.json and allows user to select
  /// which skills to install and to which models.
  Future<void> installSkillsInteractive() async {
    logger
        .warn('⚠️  EXPERIMENTAL: This feature has not been fully tested yet.');
    final loader = SkillsLoader(
      skillsBasePath: skillsBasePath,
      bundledSkillsPath: bundledSkillsPath,
    );
    final index = await loader.load();

    if (index == null || index.skills.isEmpty) {
      logger.error('No skills found in registry.');
      logger.detail('Create a skills.json file in your skills directory.');
      return;
    }

    // Show available skills
    logger.section('📚 Available Skills');
    for (var i = 0; i < index.skills.length; i++) {
      final skill = index.skills[i];
      print(
          '  \x1B[36m${i + 1}.\x1B[0m \x1B[1m${skill.name}\x1B[0m \x1B[90m- ${skill.description}\x1B[0m');
    }
    print('  \x1B[33m${index.skills.length + 1}. 🌟 All skills\x1B[0m');

    stdout.write(
        '\n\x1B[1m❯\x1B[0m Select skills to install (comma-separated numbers, or ${index.skills.length + 1} for all): ');
    final input = stdin.readLineSync()?.trim() ?? '';

    List<SkillEntry> selectedSkills = [];
    if (input == '${index.skills.length + 1}' || input.toLowerCase() == 'all') {
      selectedSkills = index.skills;
    } else {
      final indices = input.split(',').map((i) => int.tryParse(i.trim()));
      for (final idx in indices) {
        if (idx != null && idx > 0 && idx <= index.skills.length) {
          selectedSkills.add(index.skills[idx - 1]);
        }
      }
    }

    if (selectedSkills.isEmpty) {
      logger.error('No skills selected.');
      return;
    }

    // Show AI models
    final models = discoverModelFolders();
    if (models.isEmpty) {
      logger.warn('⚠️  No existing AI model folders found.');
      logger.detail('Showing available AI model options for selection...');
    }

    // If empty, show all available template models instead
    final availableModels = models.isNotEmpty ? models : _getKnownAIModels();

    logger.section('🤖 Target AI Models');
    for (var i = 0; i < availableModels.length; i++) {
      final displayName =
          aiModelDisplayNames[availableModels[i]] ?? availableModels[i];
      print('  \x1B[36m${i + 1}.\x1B[0m \x1B[1m$displayName\x1B[0m');
    }
    print('  \x1B[33m${availableModels.length + 1}. 🌟 All models\x1B[0m');

    stdout.write(
        '\n\x1B[1m❯\x1B[0m Select models (comma-separated numbers, or ${availableModels.length + 1} for all): ');
    final modelInput = stdin.readLineSync()?.trim() ?? '';

    List<String> selectedModels = [];
    if (modelInput == '${availableModels.length + 1}' ||
        modelInput.toLowerCase() == 'all') {
      selectedModels = availableModels;
    } else {
      final indices = modelInput.split(',').map((i) => int.tryParse(i.trim()));
      for (final idx in indices) {
        if (idx != null && idx > 0 && idx <= availableModels.length) {
          selectedModels.add(availableModels[idx - 1]);
        }
      }
    }

    if (selectedModels.isEmpty) {
      logger.error('No models selected.');
      return;
    }

    // Check which models already have these skills installed
    final alreadyInstalled = <String, List<String>>{}; // skillId -> [models]
    final notInstalled = <String, List<String>>{}; // skillId -> [models]

    for (final skill in selectedSkills) {
      alreadyInstalled[skill.id] = [];
      notInstalled[skill.id] = [];

      for (final model in selectedModels) {
        final modelDir = Directory(p.join(projectRoot, model));
        final skillDir = Directory(p.join(modelDir.path, 'skills', skill.id));

        if (skillDir.existsSync()) {
          alreadyInstalled[skill.id]!.add(model);
        } else {
          notInstalled[skill.id]!.add(model);
        }
      }
    }

    // Check if any skills are already installed in any selected models
    final hasAnyInstalled =
        alreadyInstalled.values.any((models) => models.isNotEmpty);

    if (hasAnyInstalled) {
      logger.section('⚠️  Existing Installations Detected');
      for (final skill in selectedSkills) {
        final installed = alreadyInstalled[skill.id]!;
        if (installed.isNotEmpty) {
          final displayNames =
              installed.map((m) => aiModelDisplayNames[m] ?? m).join(', ');
          print(
              '  \x1B[33m⚡\x1B[0m \x1B[1m${skill.name}\x1B[0m is already in: \x1B[36m$displayNames\x1B[0m');
        }
      }
      print('');
      print('\x1B[1mWhat would you like to do?\x1B[0m');
      print(
          '  \x1B[36m1.\x1B[0m Skip already installed models (install to new models only)');
      print('  \x1B[36m2.\x1B[0m Overwrite all selected models');
      print('  \x1B[31m3.\x1B[0m Cancel installation');
      stdout.write('\n\x1B[1m❯\x1B[0m Select option (1, 2, or 3): ');
      final overwriteInput = stdin.readLineSync()?.trim() ?? '';

      if (overwriteInput == '3') {
        logger.info('Installation cancelled.');
        return;
      } else if (overwriteInput == '1') {
        // Filter to only install to models that don't have the skill
        final modelsToInstall = <String>{};
        for (final skill in selectedSkills) {
          modelsToInstall.addAll(notInstalled[skill.id]!);
        }

        if (modelsToInstall.isEmpty) {
          logger
              .info('All selected models already have these skills installed.');
          return;
        }

        selectedModels = modelsToInstall.toList()..sort();
        logger.info('Installing to ${selectedModels.length} new model(s)...');
      }
      // If overwriteInput == '2', continue with all selectedModels
    }

    // If multiple models selected, ask about installation mode
    String? primaryModel;
    bool useSymlinks = false;

    if (selectedModels.length > 1) {
      // Check for existing installations among already-installed models
      final existingWithFiles = <String>[];
      for (final skill in selectedSkills) {
        for (final model in alreadyInstalled[skill.id]!) {
          final skillDir =
              Directory(p.join(projectRoot, model, 'skills', skill.id));
          if (skillDir.existsSync() && !existingWithFiles.contains(model)) {
            existingWithFiles.add(model);
          }
        }
      }

      logger.section('📦 Installation Mode');
      print('You selected \x1B[1m${selectedModels.length}\x1B[0m models.');
      print('');

      // Build installation options based on existing installations
      final options = <String>[
        '\x1B[36m1.\x1B[0m Copy skill files to each model folder',
        if (existingWithFiles.isNotEmpty)
          '\x1B[36m2.\x1B[0m Symlink all models to an existing installation',
        '\x1B[36m${existingWithFiles.isNotEmpty ? 3 : 2}.\x1B[0m Install to one new model and symlink to others',
      ];

      print('\x1B[1mChoose installation method:\x1B[0m');
      for (final option in options) {
        print('  $option');
      }

      stdout.write(
          '\n\x1B[1m❯\x1B[0m Select mode (${existingWithFiles.isNotEmpty ? '1-3' : '1-2'}): ');
      final modeInput = stdin.readLineSync()?.trim() ?? '';

      if (modeInput == '2' && existingWithFiles.isNotEmpty) {
        // Use existing installation as symlink source
        useSymlinks = true;
        logger.section('🔗 Select Source for Symlinks');
        print('These models already have the skill files:');
        for (var i = 0; i < existingWithFiles.length; i++) {
          final displayName =
              aiModelDisplayNames[existingWithFiles[i]] ?? existingWithFiles[i];
          print('  \x1B[36m${i + 1}.\x1B[0m \x1B[1m$displayName\x1B[0m');
        }
        stdout.write('\n\x1B[1m❯\x1B[0m Select source model: ');
        final sourceInput = stdin.readLineSync()?.trim() ?? '';
        final sourceIdx = int.tryParse(sourceInput);

        if (sourceIdx != null &&
            sourceIdx > 0 &&
            sourceIdx <= existingWithFiles.length) {
          primaryModel = existingWithFiles[sourceIdx - 1];
          // Only symlink to models that don't have it yet
          selectedModels = selectedModels
              .where((m) =>
                  !alreadyInstalled.values.any((models) => models.contains(m)))
              .toList();
        } else {
          logger.error('Invalid selection.');
          return;
        }
      } else if ((modeInput == '2' && existingWithFiles.isEmpty) ||
          modeInput == '3') {
        // Install to new primary and symlink to others
        useSymlinks = true;
        logger.section('🎯 Primary Installation Target');
        print('Select which model to install the skill files into:');
        for (var i = 0; i < selectedModels.length; i++) {
          final displayName =
              aiModelDisplayNames[selectedModels[i]] ?? selectedModels[i];
          print('  ${i + 1}. $displayName');
        }
        stdout.write('\nSelect primary model: ');
        final primaryInput = stdin.readLineSync()?.trim() ?? '';
        final primaryIdx = int.tryParse(primaryInput);

        if (primaryIdx != null &&
            primaryIdx > 0 &&
            primaryIdx <= selectedModels.length) {
          primaryModel = selectedModels[primaryIdx - 1];
        } else {
          logger.error('Invalid selection.');
          return;
        }
      }
    }

    // Install each skill
    for (final skill in selectedSkills) {
      if (useSymlinks && primaryModel != null) {
        // Install to primary model first
        await installSkill(skillId: skill.id, model: primaryModel);

        // Create symlinks for other models
        for (final model in selectedModels) {
          if (model != primaryModel) {
            await symlinkSkill(
              skillId: skill.id,
              targetModel: primaryModel,
              model: model,
            );
          }
        }
      } else {
        // Copy to each model
        for (final model in selectedModels) {
          await installSkill(skillId: skill.id, model: model);
        }
      }
    }

    logger.success(
        '✓ Installed ${selectedSkills.length} skill(s) to ${selectedModels.length} model(s)');
  }

  /// Interactive installation flow.
  ///
  /// Shows numbered menu of available AI models and guides user through
  /// selection and installation mode choice.
  Future<void> installSkillInteractive({required String skillId}) async {
    logger
        .warn('⚠️  EXPERIMENTAL: This feature has not been fully tested yet.');
    final models = discoverModelFolders();

    if (models.isEmpty) {
      logger.error('No AI model folders could be discovered or created.');
      return;
    }

    logger.section('🎯 Installing Skill: $skillId');
    logger.detail('Available AI models:');
    for (var i = 0; i < models.length; i++) {
      final displayName = aiModelDisplayNames[models[i]] ?? models[i];
      print('  ${i + 1}. $displayName');
    }
    print('  ${models.length + 1}. All models');

    stdout.write(
        '\nSelect models (comma-separated numbers, or ${models.length + 1} for all): ');
    final input = stdin.readLineSync()?.trim() ?? '';

    List<String> selectedModels = [];
    if (input == '${models.length + 1}' || input.toLowerCase() == 'all') {
      selectedModels = models;
    } else {
      final indices = input.split(',').map((i) => int.tryParse(i.trim()));
      for (final idx in indices) {
        if (idx != null && idx > 0 && idx <= models.length) {
          selectedModels.add(models[idx - 1]);
        }
      }
    }

    if (selectedModels.isEmpty) {
      logger.error('No models selected.');
      return;
    }

    if (selectedModels.length == 1) {
      // Install to single model
      await installSkill(skillId: skillId, model: selectedModels[0]);
    } else {
      // Multiple models - ask about installation mode
      logger.section('Installation Mode');
      print('1. Copy skill to each model (separate copies)');
      print('2. Install to first model + symlink to others');
      stdout.write('\nSelect mode (1 or 2): ');
      final mode = stdin.readLineSync()?.trim() ?? '1';

      if (mode == '2') {
        // Install to first model, symlink to others
        final sourceModel = selectedModels[0];
        await installSkill(skillId: skillId, model: sourceModel);

        for (var i = 1; i < selectedModels.length; i++) {
          await symlinkSkill(
            skillId: skillId,
            targetModel: sourceModel,
            model: selectedModels[i],
          );
        }
      } else {
        // Copy to each model
        for (final model in selectedModels) {
          await installSkill(skillId: skillId, model: model);
        }
      }
    }
  }

  /// Interactive uninstall flow.
  ///
  /// Shows menu of installed skills and models, letting user choose what to remove.
  Future<void> uninstallSkillsInteractive() async {
    // Get list of installed skills
    final installedSkills = <String, Set<String>>{}; // skillId -> {models}

    final models = discoverModelFolders();
    for (final model in models) {
      final skillsDir = Directory(p.join(projectRoot, model, 'skills'));
      if (skillsDir.existsSync()) {
        for (final entity in skillsDir.listSync()) {
          if (entity is Directory) {
            final skillId = p.basename(entity.path);
            installedSkills.putIfAbsent(skillId, () => {}).add(model);
          }
        }
      }
    }

    if (installedSkills.isEmpty) {
      logger.info('No skills currently installed.');
      return;
    }

    // Show installed skills
    logger.section('📚 Installed Skills');
    final skillList = installedSkills.keys.toList()..sort();
    for (var i = 0; i < skillList.length; i++) {
      final skill = skillList[i];
      final modelCount = installedSkills[skill]!.length;
      print(
          '  ${i + 1}. $skill (installed in $modelCount model${modelCount == 1 ? '' : 's'})');
    }
    print('  ${skillList.length + 1}. All skills');

    stdout.write(
        '\nSelect skills to remove (comma-separated numbers, or ${skillList.length + 1} for all): ');
    final skillInput = stdin.readLineSync()?.trim() ?? '';

    List<String> selectedSkills = [];
    if (skillInput == '${skillList.length + 1}' ||
        skillInput.toLowerCase() == 'all') {
      selectedSkills = skillList;
    } else {
      final indices = skillInput.split(',').map((i) => int.tryParse(i.trim()));
      for (final idx in indices) {
        if (idx != null && idx > 0 && idx <= skillList.length) {
          selectedSkills.add(skillList[idx - 1]);
        }
      }
    }

    if (selectedSkills.isEmpty) {
      logger.error('No skills selected.');
      return;
    }

    // Collect all models where selected skills are installed
    final modelsWithSelectedSkills = <String>{};
    for (final skillId in selectedSkills) {
      modelsWithSelectedSkills.addAll(installedSkills[skillId]!);
    }

    final modelList = modelsWithSelectedSkills.toList()..sort();

    logger.section('🤖 Target AI Models');
    for (var i = 0; i < modelList.length; i++) {
      final displayName = aiModelDisplayNames[modelList[i]] ?? modelList[i];
      print('  ${i + 1}. $displayName');
    }
    print('  ${modelList.length + 1}. All models');

    stdout.write(
        '\nSelect models (comma-separated numbers, or ${modelList.length + 1} for all): ');
    final modelInput = stdin.readLineSync()?.trim() ?? '';

    List<String> selectedModels = [];
    if (modelInput == '${modelList.length + 1}' ||
        modelInput.toLowerCase() == 'all') {
      selectedModels = modelList;
    } else {
      final indices = modelInput.split(',').map((i) => int.tryParse(i.trim()));
      for (final idx in indices) {
        if (idx != null && idx > 0 && idx <= modelList.length) {
          selectedModels.add(modelList[idx - 1]);
        }
      }
    }

    if (selectedModels.isEmpty) {
      logger.error('No models selected.');
      return;
    }

    // Confirm removal
    logger.section('⚠️  Confirm Removal');
    print('You are about to remove:');
    print('  Skills: ${selectedSkills.join(', ')}');
    print(
        '  Models: ${selectedModels.map((m) => aiModelDisplayNames[m] ?? m).join(', ')}');
    print('');
    stdout.write('Are you sure? (yes/no): ');
    final confirm = stdin.readLineSync()?.trim().toLowerCase() ?? '';

    if (confirm != 'yes' && confirm != 'y') {
      logger.info('Removal cancelled.');
      return;
    }

    // Remove skills from selected models
    int removedCount = 0;
    for (final skill in selectedSkills) {
      for (final model in selectedModels) {
        try {
          await uninstallSkill(skillId: skill, model: model);
          removedCount++;
        } catch (_) {
          // Already logged in uninstallSkill
        }
      }
    }

    logger.success(
        '✓ Removed ${selectedSkills.length} skill(s) from ${selectedModels.length} model(s) ($removedCount total removals)');
  }

  /// Downloads or copies skill files from source.
  ///
  /// First tries local registry, then falls back to GitHub/remote.
  Future<void> _downloadSkillFiles(String skillId, String targetPath) async {
    // Try local registry first
    final localSkillPath = await _findLocalSkillPath(skillId);

    if (localSkillPath != null) {
      logger.detail('Copying skill from local registry: $localSkillPath');
      await _copyLocalSkillFiles(localSkillPath, targetPath);
      return;
    }

    final downloaded = await _downloadRemoteSkillFiles(skillId, targetPath);
    if (downloaded) {
      return;
    }

    logger.detail('Skill source not found. Creating placeholder...');
    await _createPlaceholderManifest(skillId, targetPath);
  }

  /// Finds local skill path by checking common locations.
  Future<String?> _findLocalSkillPath(String skillId) async {
    final explicitCandidates = <String>[
      if (bundledSkillsPath != null) p.join(bundledSkillsPath!, skillId),
      if (bundledSkillsPath != null)
        p.join(p.dirname(bundledSkillsPath!), 'skills', skillId),
      if (!_looksLikeRemoteUrl(skillsBaseUrl)) p.join(skillsBaseUrl, skillId),
      if (!_looksLikeRemoteUrl(skillsBaseUrl))
        p.join(skillsBaseUrl, 'skills', skillId),
    ];
    for (final candidate in explicitCandidates) {
      final directory = Directory(candidate);
      if (await directory.exists()) {
        return directory.path;
      }
    }

    var current = Directory(projectRoot);
    while (true) {
      final candidates = [
        p.join(current.path, 'registry', 'skills', skillId),
        p.join(current.path, 'shadcn_flutter_kit', 'flutter_shadcn_kit',
            'skills', skillId),
        p.join(current.path, 'skills', skillId),
      ];
      for (final candidatePath in candidates) {
        final candidate = Directory(candidatePath);
        if (await candidate.exists()) {
          return candidate.path;
        }
      }

      final parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      current = parent;
    }

    // Check 3: Direct path in project root
    final rootSkill = Directory(p.join(projectRoot, 'skills', skillId));
    if (await rootSkill.exists()) {
      return rootSkill.path;
    }

    return null;
  }

  Future<bool> _downloadRemoteSkillFiles(
    String skillId,
    String targetPath,
  ) async {
    if (!_looksLikeRemoteUrl(skillsBaseUrl)) {
      return false;
    }

    for (final skillBaseUrl in _remoteSkillBaseCandidates(skillId)) {
      final manifestUri = Uri.parse('$skillBaseUrl/skill.json');
      http.Response manifestResponse;
      try {
        manifestResponse = await http.get(manifestUri);
      } catch (e) {
        logger.detail('Remote skill manifest request failed: $e');
        continue;
      }
      if (manifestResponse.statusCode != HttpStatus.ok) {
        continue;
      }

      final manifest =
          jsonDecode(manifestResponse.body) as Map<String, dynamic>;
      final relativeFiles = _filesFromManifest(manifest);
      if (relativeFiles.isEmpty) {
        throw Exception(
          'Manifest must specify files to copy in the "files" key',
        );
      }

      var copied = 0;
      for (final relativePath in relativeFiles) {
        final fileUri = Uri.parse('$skillBaseUrl/$relativePath');
        final fileResponse = await http.get(fileUri);
        if (fileResponse.statusCode != HttpStatus.ok) {
          logger.detail('Skipping missing remote skill file: $relativePath');
          continue;
        }

        final destFile = File(p.join(targetPath, relativePath));
        await destFile.parent.create(recursive: true);
        await destFile.writeAsString(fileResponse.body);
        copied++;
        logger.detail('✓ Downloaded: $relativePath');
      }

      logger.success('✓ Downloaded $copied skill files');
      return true;
    }

    return false;
  }

  List<String> _remoteSkillBaseCandidates(String skillId) {
    final normalizedBase = _normalizeRemoteBaseUrl(skillsBaseUrl);
    final base = normalizedBase.replaceAll(RegExp(r'/+$'), '');
    final candidates = <String>[
      '$base/$skillId',
      '$base/skills/$skillId',
    ];

    if (base.endsWith('/$skillId')) {
      candidates.insert(0, base);
    }

    return candidates.toSet().toList();
  }

  String _normalizeRemoteBaseUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != 'github.com') {
      return url;
    }

    final segments = uri.pathSegments;
    final treeIndex = segments.indexOf('tree');
    final blobIndex = segments.indexOf('blob');
    final markerIndex = treeIndex >= 0 ? treeIndex : blobIndex;
    if (segments.length < 4 ||
        markerIndex < 2 ||
        markerIndex + 1 >= segments.length) {
      return url;
    }

    final owner = segments[0];
    final repo = segments[1];
    final ref = segments[markerIndex + 1];
    final pathSegments = segments.skip(markerIndex + 2).join('/');
    return 'https://raw.githubusercontent.com/$owner/$repo/$ref/$pathSegments';
  }

  bool _looksLikeRemoteUrl(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  List<String> _filesFromManifest(Map<String, dynamic> manifest) {
    final filesConfig = manifest['files'] as Map<String, dynamic>?;
    if (filesConfig == null) {
      return const [];
    }

    final files = <String>[];
    final main = filesConfig['main'];
    if (main is String) {
      files.add(main);
    }

    final installation = filesConfig['installation'];
    if (installation is String) {
      files.add(installation);
    }

    final readme = filesConfig['readme'];
    if (readme is String) {
      files.add(readme);
    }

    final references = filesConfig['references'];
    if (references is Map<String, dynamic>) {
      for (final entry in references.entries) {
        if (entry.key != 'schemas' && entry.value is String) {
          files.add(entry.value as String);
        }
      }
    }

    return files;
  }

  /// Copies skill files from local registry to target path.
  ///
  /// Requires either skill.json or skill.yaml manifest in the source path.
  /// The manifest's 'files' key determines which files to copy.
  Future<void> _copyLocalSkillFiles(
      String sourcePath, String targetPath) async {
    final files = <File>[];

    // Check for skill.json first, then skill.yaml
    File? manifestFile;
    final skillJsonFile = File(p.join(sourcePath, 'skill.json'));
    final skillYamlFile = File(p.join(sourcePath, 'skill.yaml'));

    if (await skillJsonFile.exists()) {
      manifestFile = skillJsonFile;
    } else if (await skillYamlFile.exists()) {
      manifestFile = skillYamlFile;
    }

    if (manifestFile == null) {
      logger.error('No skill.json or skill.yaml found in $sourcePath');
      throw Exception('Skill manifest (skill.json or skill.yaml) is required');
    }

    // Read manifest to know which files to copy
    try {
      final content = await manifestFile.readAsString();
      Map<String, dynamic>? json;

      // Parse based on file extension
      if (p.extension(manifestFile.path) == '.json') {
        json = jsonDecode(content) as Map<String, dynamic>;
      } else {
        // For YAML support, we'd use yaml package here
        // For now, log and fall back to markdown files
        logger
            .detail('YAML manifest found but YAML parsing not yet implemented');
      }

      if (json != null) {
        final filesConfig = json['files'] as Map<String, dynamic>?;

        if (filesConfig != null) {
          // Add main file
          if (filesConfig['main'] != null) {
            files.add(File(p.join(sourcePath, filesConfig['main'] as String)));
          }

          // Add installation file
          if (filesConfig['installation'] != null) {
            files.add(File(
                p.join(sourcePath, filesConfig['installation'] as String)));
          }

          // Add readme if exists
          if (filesConfig['readme'] != null) {
            final readmeFile =
                File(p.join(sourcePath, filesConfig['readme'] as String));
            if (await readmeFile.exists()) {
              files.add(readmeFile);
            }
          }

          // Add reference files (excluding schemas - that's for CLI management)
          if (filesConfig['references'] is Map) {
            final references =
                filesConfig['references'] as Map<String, dynamic>;
            for (final entry in references.entries) {
              if (entry.key != 'schemas' && entry.value is String) {
                files.add(File(p.join(sourcePath, entry.value as String)));
              }
            }
          }
        }

        // NOTE: skill.json and skill.yaml are CLI management files
        // They are NOT copied to model folders - only used by CLI to determine what to copy
        logger.detail('Using manifest: ${p.basename(manifestFile.path)}');
      } else {
        logger.detail('No files configuration found in manifest');
      }
    } catch (e) {
      logger.error('Error parsing manifest: $e');
      throw Exception('Failed to read skill manifest: $e');
    }

    // Validate that we have files to copy
    if (files.isEmpty) {
      logger.error('No files configured in manifest to copy');
      throw Exception('Manifest must specify files to copy in the "files" key');
    }

    // Copy each file maintaining directory structure
    for (final file in files) {
      if (!await file.exists()) {
        logger.detail('Skipping missing file: ${file.path}');
        continue;
      }

      final relativePath = p.relative(file.path, from: sourcePath);
      final destFile = File(p.join(targetPath, relativePath));

      // Create parent directories
      await destFile.parent.create(recursive: true);

      // Copy file
      await file.copy(destFile.path);
      logger.detail('✓ Copied: $relativePath');
    }

    logger.success('✓ Copied ${files.length} skill files');
  }

  /// Creates a placeholder manifest when skill source is not found.
  Future<void> _createPlaceholderManifest(
      String skillId, String targetPath) async {
    final manifestFile = File(p.join(targetPath, 'manifest.json'));
    await manifestFile.writeAsString('''{
  "skill": {
    "id": "$skillId",
    "version": "1.0.0",
    "name": "Skill: $skillId",
    "description": "AI skill for $skillId",
    "models": ["gpt-4", "claude-3"],
    "createdAt": "${DateTime.now().toIso8601String()}"
  },
  "files": [],
  "note": "This is a placeholder. Skill files were not found in local registry."
}
''');

    logger.detail('Placeholder manifest created at: ${manifestFile.path}');
  }
}
