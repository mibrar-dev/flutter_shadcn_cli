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

    return _build(
      namespace: token.substring(1, slash),
      componentId: token.substring(slash + 1),
    );
  }

  static QualifiedComponentRef? _build({
    required String namespace,
    required String componentId,
  }) {
    final normalizedNamespace = namespace.trim();
    final normalizedComponentId = componentId.trim();
    if (normalizedNamespace.isEmpty || normalizedComponentId.isEmpty) {
      return null;
    }
    if (normalizedNamespace.contains('/') ||
        normalizedNamespace.contains(':') ||
        normalizedNamespace.startsWith('@') ||
        normalizedComponentId.contains('/')) {
      return null;
    }

    return QualifiedComponentRef(
      namespace: normalizedNamespace,
      componentId: normalizedComponentId,
    );
  }
}
