import 'package:flutter_shadcn_cli/src/application/dto/qualified_component_ref.dart';

class ComponentRefNormalizer {
  const ComponentRefNormalizer._();

  static QualifiedComponentRef? parse(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    if (trimmed.startsWith('@')) {
      return _parseAtRef(trimmed);
    }

    final colon = trimmed.indexOf(':');
    if (colon == -1) {
      return null;
    }

    return _build(
      namespace: trimmed.substring(0, colon),
      componentId: trimmed.substring(colon + 1),
      version: null,
    );
  }

  static bool looksQualified(String token) {
    final trimmed = token.trim();
    return trimmed.startsWith('@') || trimmed.contains(':');
  }

  static QualifiedComponentRef? _parseAtRef(String token) {
    final slash = token.indexOf('/');
    if (slash <= 1 || slash == token.length - 1) {
      return null;
    }
    if (token.indexOf('/', slash + 1) != -1) {
      return null;
    }

    final namespace = token.substring(1, slash);
    final componentAndVersion = token.substring(slash + 1);
    final versionSeparator = componentAndVersion.lastIndexOf('@');
    final componentId = versionSeparator == -1
        ? componentAndVersion
        : componentAndVersion.substring(0, versionSeparator);
    final version = versionSeparator == -1
        ? null
        : componentAndVersion.substring(versionSeparator + 1);

    return _build(
      namespace: namespace,
      componentId: componentId,
      version: version,
    );
  }

  static QualifiedComponentRef? _build({
    required String namespace,
    required String componentId,
    required String? version,
  }) {
    final normalizedNamespace = namespace.trim();
    final normalizedComponentId = componentId.trim();
    final normalizedVersion = version?.trim();
    if (normalizedNamespace.isEmpty || normalizedComponentId.isEmpty) {
      return null;
    }
    if (normalizedVersion != null && normalizedVersion.isEmpty) {
      return null;
    }
    if (normalizedNamespace.contains('/') ||
        normalizedNamespace.contains(':') ||
        normalizedNamespace.startsWith('@') ||
        normalizedComponentId.contains('/') ||
        normalizedComponentId.contains('@') ||
        (normalizedVersion?.contains('/') ?? false) ||
        (normalizedVersion?.contains('@') ?? false)) {
      return null;
    }

    return QualifiedComponentRef(
      namespace: normalizedNamespace,
      componentId: normalizedComponentId,
      version: normalizedVersion,
    );
  }
}
