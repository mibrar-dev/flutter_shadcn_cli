part of 'installer.dart';

class _InstalledLocaleResource {
  const _InstalledLocaleResource({
    required this.locale,
    required this.format,
    required this.source,
    required this.destination,
    required this.required,
    required this.addedKeys,
    this.sha256,
  });

  final String locale;
  final String format;
  final String source;
  final String destination;
  final bool required;
  final List<String> addedKeys;
  final String? sha256;

  Map<String, dynamic> toJson() {
    return {
      'locale': locale,
      'format': format,
      'source': source,
      'destination': destination,
      'required': required,
      'addedKeys': addedKeys,
      if (sha256 != null) 'sha256': sha256,
    };
  }
}

class _L10nConfig {
  const _L10nConfig({
    required this.arbDir,
    required this.templateArbFile,
    required this.outputLocalizationFile,
  });

  final String arbDir;
  final String templateArbFile;
  final String outputLocalizationFile;
}

extension InstallerLocalePart on Installer {
  Future<List<Map<String, dynamic>>> _installLocaleResources(
    Component component,
  ) async {
    final locale = component.locale;
    if (locale == null || !locale.hasResources) {
      return const [];
    }

    final config = _loadL10nConfig();
    final installed = <_InstalledLocaleResource>[];
    for (final resource in locale.resources) {
      final normalizedFormat = resource.format.trim().toLowerCase();
      if (normalizedFormat != 'arb' && normalizedFormat != 'json') {
        throw LocaleInstallException(
          code: 'unsupported-format',
          message:
              'Unsupported locale resource format "${resource.format}" for ${component.id}.',
        );
      }
      final data = await _readLocaleResource(resource);
      installed.add(
        await _mergeLocaleResourceIntoArb(
          config: config,
          resource: resource,
          data: data,
          format: normalizedFormat,
        ),
      );
    }

    if (installed.isNotEmpty) {
      logger.detail('Merged locale resources for ${component.id}.');
    }
    return installed.map((entry) => entry.toJson()).toList();
  }

  _L10nConfig _loadL10nConfig() {
    final file = File(_resolveProjectPath('l10n.yaml'));
    if (!file.existsSync()) {
      throw const LocaleInstallException(
        code: 'missing-l10n-config',
        message:
            'Locale resources require l10n.yaml. Run flutter_shadcn locale init, '
            'or create l10n.yaml with arb-dir, template-arb-file, and '
            'output-localization-file before installing locale-aware components.',
      );
    }
    final parsed = loadYaml(file.readAsStringSync());
    if (parsed is! YamlMap) {
      throw const LocaleInstallException(
        code: 'invalid-l10n-config',
        message: 'l10n.yaml must be a YAML map.',
      );
    }
    final arbDir = parsed['arb-dir']?.toString().trim();
    final templateArbFile = parsed['template-arb-file']?.toString().trim();
    final outputLocalizationFile =
        parsed['output-localization-file']?.toString().trim();
    if (arbDir == null || arbDir.isEmpty) {
      throw const LocaleInstallException(
        code: 'missing-l10n-arb-dir',
        message: 'l10n.yaml must define arb-dir.',
      );
    }
    if (templateArbFile == null || templateArbFile.isEmpty) {
      throw const LocaleInstallException(
        code: 'missing-l10n-template-arb-file',
        message: 'l10n.yaml must define template-arb-file.',
      );
    }
    if (outputLocalizationFile == null || outputLocalizationFile.isEmpty) {
      throw const LocaleInstallException(
        code: 'missing-l10n-output-localization-file',
        message: 'l10n.yaml must define output-localization-file.',
      );
    }
    ProjectPathGuard.resolveSafeWritePath(
      projectRoot: targetDir,
      destinationRelativePath: arbDir,
    );
    return _L10nConfig(
      arbDir: arbDir,
      templateArbFile: templateArbFile,
      outputLocalizationFile: outputLocalizationFile,
    );
  }

  Future<Map<String, dynamic>> _readLocaleResource(
    ComponentLocaleResource resource,
  ) async {
    final bytes = await registry.readSourceBytes(resource.source);
    if (resource.sha256 != null && resource.sha256!.isNotEmpty) {
      final digest = sha256.convert(bytes).toString().toLowerCase();
      if (digest != resource.sha256!.toLowerCase()) {
        throw LocaleInstallException(
          code: 'hash-mismatch',
          message: 'Locale resource hash mismatch for ${resource.source}.',
        );
      }
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw LocaleInstallException(
        code: 'invalid-resource-json',
        message: 'Locale resource ${resource.source} must be a JSON object.',
      );
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<_InstalledLocaleResource> _mergeLocaleResourceIntoArb({
    required _L10nConfig config,
    required ComponentLocaleResource resource,
    required Map<String, dynamic> data,
    required String format,
  }) async {
    final targetFileName =
        format == 'arb' && resource.destinationName?.trim().isNotEmpty == true
            ? resource.destinationName!.trim()
            : _arbFileForLocale(config.templateArbFile, resource.locale);
    final targetRel = p.join(
      config.arbDir,
      targetFileName,
    );
    final target = File(_resolveProjectPath(targetRel));
    if (!target.parent.existsSync()) {
      target.parent.createSync(recursive: true);
    }
    final existing = target.existsSync()
        ? _readJsonObjectFile(target, 'ARB file ${target.path}')
        : <String, dynamic>{};
    final addedKeys = <String>[];
    for (final entry in data.entries) {
      if (!existing.containsKey(entry.key)) {
        existing[entry.key] = entry.value;
        addedKeys.add(entry.key);
      }
    }
    await target.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(existing)}\n',
    );
    addedKeys.sort();
    return _InstalledLocaleResource(
      locale: resource.locale,
      format: format,
      source: resource.source,
      destination: targetRel,
      required: resource.required,
      addedKeys: addedKeys,
      sha256: resource.sha256,
    );
  }

  Map<String, dynamic> _readJsonObjectFile(File file, String label) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      throw LocaleInstallException(
        code: 'invalid-json-object',
        message: '$label must contain a JSON object.',
      );
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  String _arbFileForLocale(String templateArbFile, String locale) {
    final normalizedLocale = locale.replaceAll('-', '_');
    final extension = p.extension(templateArbFile);
    final stem = p.basenameWithoutExtension(templateArbFile);
    final match = RegExp(
      r'^(.*)_([A-Za-z]{2,3}(?:_[A-Za-z0-9]+)*)$',
    ).firstMatch(stem);
    final prefix = match == null ? stem : match.group(1)!;
    return '${prefix}_$normalizedLocale${extension.isEmpty ? '.arb' : extension}';
  }

  Future<void> _removeLocaleResources(String componentId) async {
    final manifestFile = _componentManifestFile(componentId);
    if (!manifestFile.existsSync()) {
      return;
    }
    final manifest = _readJsonObjectFile(
      manifestFile,
      'Component manifest ${manifestFile.path}',
    );
    final locale = manifest['locale'];
    if (locale is! Map) {
      return;
    }
    final resources = locale['resourcesInstalled'];
    if (resources is! List) {
      return;
    }
    final ownedElsewhere = await _localeKeysOwnedByOtherComponents(componentId);
    for (final item in resources) {
      if (item is! Map) {
        continue;
      }
      final destination = item['destination']?.toString();
      final format = item['format']?.toString().toLowerCase();
      if (destination == null || destination.isEmpty) {
        continue;
      }
      if (format == 'arb' || format == 'json') {
        await _removeOwnedArbKeys(
          destination: destination,
          keys: _localeStringList(item['addedKeys']),
          ownedElsewhere: ownedElsewhere[destination] ?? const <String>{},
        );
      }
    }
  }

  Future<Map<String, Set<String>>> _localeKeysOwnedByOtherComponents(
    String componentId,
  ) async {
    final result = <String, Set<String>>{};
    final dir = _componentManifestDirectory();
    if (!dir.existsSync()) {
      return result;
    }
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }
      final id = p.basenameWithoutExtension(entity.path);
      if (id == componentId) {
        continue;
      }
      try {
        final manifest = _readJsonObjectFile(entity, 'Component manifest');
        final locale = manifest['locale'];
        final resources = locale is Map ? locale['resourcesInstalled'] : null;
        if (resources is! List) {
          continue;
        }
        for (final item in resources) {
          if (item is! Map) {
            continue;
          }
          final destination = item['destination']?.toString();
          if (destination == null || destination.isEmpty) {
            continue;
          }
          result
              .putIfAbsent(destination, () => <String>{})
              .addAll(_localeStringList(item['addedKeys']));
        }
      } catch (_) {}
    }
    return result;
  }

  Future<void> _removeOwnedArbKeys({
    required String destination,
    required List<String> keys,
    required Set<String> ownedElsewhere,
  }) async {
    if (keys.isEmpty) {
      return;
    }
    final target = File(_resolveProjectPath(destination));
    if (!target.existsSync()) {
      return;
    }
    final data = _readJsonObjectFile(target, 'ARB file ${target.path}');
    var changed = false;
    for (final key in keys) {
      if (ownedElsewhere.contains(key)) {
        continue;
      }
      if (data.remove(key) != null) {
        changed = true;
      }
    }
    if (changed) {
      await target.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(data)}\n',
      );
    }
  }

  List<String> _localeStringList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value.map((entry) => entry.toString()).toList();
  }
}

class LocaleInstallException implements Exception {
  final String code;
  final String message;

  const LocaleInstallException({
    required this.code,
    required this.message,
  });

  @override
  String toString() => 'LocaleInstallException($code): $message';
}
