import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:path/path.dart' as p;

String? optionalStringOption(ArgResults? args, String name) {
  if (args == null) {
    return null;
  }
  try {
    return args[name] as String?;
  } on ArgumentError {
    return null;
  }
}

bool optionalBoolOption(ArgResults? args, String name) {
  if (args == null) {
    return false;
  }
  try {
    return args[name] == true;
  } on ArgumentError {
    return false;
  }
}

bool wasOptionalParsed(ArgResults? args, String name) {
  if (args == null) {
    return false;
  }
  try {
    return args.wasParsed(name);
  } on ArgumentError {
    return false;
  }
}

bool hasConfiguredRegistryMap(ShadcnConfig config) {
  final registries = config.registries;
  if (registries == null || registries.isEmpty) {
    return false;
  }
  for (final entry in registries.values) {
    if ((entry.registryPath?.trim().isNotEmpty ?? false) ||
        (entry.registryUrl?.trim().isNotEmpty ?? false) ||
        (entry.baseUrl?.trim().isNotEmpty ?? false)) {
      return true;
    }
  }
  return false;
}

bool isDefaultNamespaceAliasAllowed(String namespace, ShadcnConfig config) {
  final trimmed = namespace.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final defaultNamespace = config.effectiveDefaultNamespace;
  return trimmed == defaultNamespace || trimmed == 'shadcn';
}

Set<String> parseFileKindOptions(
  List rawValues, {
  required String optionName,
}) {
  final result = <String>{};
  for (final raw in rawValues) {
    final value = raw.toString();
    final parts = value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty);
    for (final part in parts) {
      final normalized = normalizeFileKindToken(part);
      if (normalized == null) {
        stderr.writeln(
          'Error: --$optionName supports only readme, preview, meta (got "$part").',
        );
        exit(ExitCodes.usage);
      }
      result.add(normalized);
    }
  }
  return result;
}

String? normalizeFileKindToken(String raw) {
  final token = raw.trim().toLowerCase();
  switch (token) {
    case 'readme':
    case 'docs':
      return 'readme';
    case 'preview':
    case 'previews':
      return 'preview';
    case 'meta':
    case 'metadata':
      return 'meta';
    default:
      return null;
  }
}

String selectedNamespaceForCommand(ArgResults args, ShadcnConfig config) {
  final fromFlag = (args['registry-name'] as String?)?.trim();
  if (fromFlag != null && fromFlag.isNotEmpty) {
    return fromFlag;
  }
  return config.effectiveDefaultNamespace;
}

Map<String, String> parseAliasPairs(List<String> entries) {
  final aliases = <String, String>{};
  for (final entry in entries) {
    final trimmed = entry.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final parts = trimmed.split('=');
    if (parts.length != 2) {
      continue;
    }
    final key = parts.first.trim();
    final value = parts.last.trim();
    if (key.isEmpty || value.isEmpty) {
      continue;
    }
    aliases[key] = stripLibPrefix(value);
  }
  return aliases;
}

String expandAliasPath(String path, Map<String, String> aliases) {
  if (aliases.isEmpty) {
    return path;
  }
  if (path.startsWith('@')) {
    final index = path.indexOf('/');
    final name = index == -1 ? path.substring(1) : path.substring(1, index);
    final aliasPath = aliases[name];
    if (aliasPath != null) {
      final suffix = index == -1 ? '' : path.substring(index + 1);
      return suffix.isEmpty ? aliasPath : p.join(aliasPath, suffix);
    }
  }
  return path;
}

bool isLibPath(String path) {
  if (path.startsWith('lib/')) {
    return true;
  }
  if (p.isAbsolute(path)) {
    return false;
  }
  if (path.startsWith('..')) {
    return false;
  }
  return true;
}

String ensureLibPrefix(String path) {
  if (path.startsWith('lib/')) {
    return path;
  }
  if (p.isAbsolute(path)) {
    return path;
  }
  return p.join('lib', path);
}

String stripLibPrefix(String value) {
  final normalized = p.normalize(value);
  if (normalized == 'lib') {
    return '';
  }
  if (normalized.startsWith('lib${p.separator}')) {
    return normalized.substring('lib'.length + 1);
  }
  return normalized;
}
