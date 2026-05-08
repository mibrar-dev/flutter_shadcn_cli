part of 'installer.dart';

extension InstallerConfigPart on Installer {
  Future<void> _ensureConfig() async {
    final existing = await ShadcnConfig.load(targetDir);

    final resolvedAliases = _promptAliases(existing.pathAliases ?? const {});

    final resolvedInstallPath = _promptPath(
      label:
          'Component install path inside lib/ (e.g. lib/ui/shadcn or lib/pages/docs)',
      current: existing.installPath ?? _defaultInstallPath,
      requireLib: true,
      aliases: resolvedAliases,
    );
    final resolvedSharedPath = _promptPath(
      label: 'Shared files path inside lib/ (e.g. lib/ui/shadcn/shared)',
      current: existing.sharedPath ?? _defaultSharedPath,
      requireLib: true,
      aliases: resolvedAliases,
    );

    final includeReadme = _promptYesNo(
      'Include README.md files for each component? (docs only)',
      defaultValue: existing.includeReadme ?? false,
    );
    final includeMeta = _promptYesNo(
      'Include meta.json files (used by the CLI to track installs)?',
      defaultValue: existing.includeMeta ?? true,
    );
    final includePreview = _promptYesNo(
      'Include preview.dart files (gallery previews)?',
      defaultValue: existing.includePreview ?? false,
    );

    String? prefix = existing.classPrefix;
    if (prefix == null || prefix.isEmpty) {
      final defaultPrefix = _defaultPrefix();
      stdout.write(
        'App class prefix for widgets (optional, e.g. $defaultPrefix). Enter to skip: ',
      );
      final input = stdin.readLineSync()?.trim();
      if (input != null && input.isNotEmpty) {
        prefix = _sanitizePrefix(input);
      }
    }

    await ShadcnConfig.save(
      targetDir,
      existing.copyWith(
        classPrefix: prefix,
        installPath: resolvedInstallPath,
        sharedPath: resolvedSharedPath,
        includeReadme: includeReadme,
        includeMeta: includeMeta,
        includePreview: includePreview,
        pathAliases: resolvedAliases.isEmpty ? null : resolvedAliases,
      ),
    );
    _cachedConfig = await ShadcnConfig.load(targetDir);
  }

  Future<void> _ensureConfigDefaults() async {
    final existing = await ShadcnConfig.load(targetDir);
    await ShadcnConfig.save(
      targetDir,
      existing.copyWith(
        installPath: existing.installPath ?? _defaultInstallPath,
        sharedPath: existing.sharedPath ?? _defaultSharedPath,
        includeReadme: existing.includeReadme ?? false,
        includeMeta: existing.includeMeta ?? true,
        includePreview: existing.includePreview ?? false,
      ),
    );
    _cachedConfig = await ShadcnConfig.load(targetDir);
  }

  Future<void> _ensureConfigOverrides(InitConfigOverrides overrides) async {
    final existing = await ShadcnConfig.load(targetDir);
    final normalizedInstall = _normalizePathOverride(
      overrides.installPath,
      _defaultInstallPath,
    );
    final normalizedShared = _normalizePathOverride(
      overrides.sharedPath,
      _defaultSharedPath,
    );

    final normalizedAliases = overrides.pathAliases?.map(
      (key, value) => MapEntry(key, _stripLibPrefix(value)),
    );

    await ShadcnConfig.save(
      targetDir,
      existing.copyWith(
        installPath: normalizedInstall,
        sharedPath: normalizedShared,
        includeReadme: overrides.includeReadme ?? existing.includeReadme,
        includeMeta: overrides.includeMeta ?? existing.includeMeta,
        includePreview: overrides.includePreview ?? existing.includePreview,
        classPrefix: overrides.classPrefix ?? existing.classPrefix,
        pathAliases: normalizedAliases ?? existing.pathAliases,
      ),
    );
    _cachedConfig = await ShadcnConfig.load(targetDir);
  }

  String _normalizePathOverride(String? value, String fallback) {
    if (value == null || value.trim().isEmpty) {
      return fallback;
    }
    final trimmed = _stripLibPrefix(value.trim());
    return p.join('lib', trimmed);
  }

  String _stripLibPrefix(String value) {
    final normalized = p.normalize(value);
    if (normalized == 'lib') {
      return '';
    }
    if (normalized.startsWith('lib${p.separator}')) {
      return normalized.substring('lib'.length + 1);
    }
    return normalized;
  }

  String _defaultPrefix() {
    final pubspec = File(p.join(targetDir, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      return 'App';
    }
    final lines = pubspec.readAsLinesSync();
    for (final line in lines) {
      if (line.startsWith('name:')) {
        final name = line.split(':').sublist(1).join(':').trim();
        return _toPascalCase(name);
      }
    }
    return 'App';
  }

  String _sanitizePrefix(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (cleaned.isEmpty) {
      return 'App';
    }
    return _toPascalCase(cleaned);
  }

  String _toPascalCase(String input) {
    final parts = input.split(RegExp(r'[^A-Za-z0-9]+'));
    final buffer = StringBuffer();
    for (final part in parts) {
      if (part.isEmpty) {
        continue;
      }
      buffer.write(part[0].toUpperCase());
      buffer.write(part.substring(1));
    }
    return buffer.toString();
  }

  String _promptPath({
    required String label,
    required String current,
    bool requireLib = false,
    Map<String, String>? aliases,
  }) {
    while (true) {
      stdout.write('$label (default: $current). Enter to keep: ');
      final input = stdin.readLineSync()?.trim();
      if (input == null || input.isEmpty) {
        return current;
      }
      final resolved = _expandAliases(input, aliases);
      if (!requireLib) {
        return input;
      }
      final normalized = p.normalize(resolved);
      if (normalized == 'lib' || normalized.startsWith('lib${p.separator}')) {
        return input;
      }
      logger.warn('Path must start with lib/. Try again.');
    }
  }

  Map<String, String> _promptAliases(Map<String, String> current) {
    if (current.isNotEmpty) {
      stdout.write(
        'Path aliases (current: ${_formatAliases(current)}). Format: name=lib/path. Enter to keep: ',
      );
    } else {
      stdout.write(
        'Path aliases (optional). Format: name=lib/path (e.g. ui=lib/ui, hooks=lib/hooks): ',
      );
    }
    final input = stdin.readLineSync()?.trim();
    if (input == null || input.isEmpty) {
      return current;
    }
    return _parseAliases(input);
  }

  Map<String, String> _parseAliases(String input) {
    final aliases = <String, String>{};
    final entries = input.split(',');
    for (final entry in entries) {
      final trimmed = entry.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final parts = trimmed.split('=');
      if (parts.length != 2) {
        logger.warn('Invalid alias format: "$trimmed". Use name=lib/path.');
        continue;
      }
      final name = parts.first.trim();
      final path = parts.last.trim();
      if (name.isEmpty || path.isEmpty) {
        continue;
      }
      final normalized = p.normalize(path);
      if (normalized != 'lib' && !normalized.startsWith('lib${p.separator}')) {
        logger.warn('Alias "$name" must point inside lib/. Skipping.');
        continue;
      }
      aliases[name] = path;
    }
    return aliases;
  }

  String _formatAliases(Map<String, String> aliases) {
    final entries = aliases.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => '${e.key}=${e.value}').join(', ');
  }

  String _expandAliases(String path, Map<String, String>? aliases) {
    return _configResolver.expandAliases(path, aliases);
  }

  bool _promptYesNo(String label, {required bool defaultValue}) {
    final defaultLabel = defaultValue ? 'Y' : 'n';
    stdout.write('$label [$defaultLabel/${defaultValue ? 'n' : 'Y'}]: ');
    final input = stdin.readLineSync()?.trim().toLowerCase();
    if (input == null || input.isEmpty) {
      return defaultValue;
    }
    return input.startsWith('y');
  }

  void _printInitSummary(ShadcnConfig config, String? themePreset) {
    logger.section('Init summary');
    logger.info('  installPath: ${config.installPath ?? _defaultInstallPath}');
    logger.info('  sharedPath: ${config.sharedPath ?? _defaultSharedPath}');
    logger.info(
        '  includeReadme: ${config.includeReadme ?? false ? 'yes' : 'no'}');
    logger.info('  includeMeta: ${config.includeMeta ?? true ? 'yes' : 'no'}');
    logger.info(
        '  includePreview: ${config.includePreview ?? false ? 'yes' : 'no'}');
    if (config.classPrefix != null && config.classPrefix!.isNotEmpty) {
      logger.info('  classPrefix: ${config.classPrefix}');
    }
    if (config.pathAliases != null && config.pathAliases!.isNotEmpty) {
      logger.info('  pathAliases: ${_formatAliases(config.pathAliases!)}');
    }
    if (themePreset != null && themePreset.isNotEmpty) {
      logger.info('  themePreset: $themePreset');
    }
    logger.info(
        '  shared core: theme, util, color_extensions, form_control, form_value_supplier');
    logger.info('  dependencies: data_widget, gap');
  }

  bool _confirmInitProceed() {
    stdout.write('Proceed with initialization? [Y/n]: ');
    final input = stdin.readLineSync()?.trim().toLowerCase();
    if (input == null || input.isEmpty) {
      return true;
    }
    return input.startsWith('y');
  }

  String _typeArgsFromParams(String params) {
    final trimmed = params.replaceAll('<', '').replaceAll('>', '');
    final parts = trimmed.split(',');
    final args = <String>[];
    for (final part in parts) {
      final token = part.trim().split(' ').first;
      if (token.isNotEmpty) {
        args.add(token);
      }
    }
    return '<${args.join(', ')}>';
  }
}
