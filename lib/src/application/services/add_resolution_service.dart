import 'package:flutter_shadcn_cli/src/application/dto/add_request.dart';
import 'package:flutter_shadcn_cli/src/application/dto/qualified_component_ref.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/core/utils/component_ref_normalizer.dart';

typedef ComponentExistsInNamespace = Future<bool> Function(
  String namespace,
  String componentId,
);

class AddResolutionService {
  const AddResolutionService();

  static QualifiedComponentRef? parseQualifiedComponentRef(String token) {
    return ComponentRefNormalizer.parse(token);
  }

  Future<List<AddRequest>> resolveAddRequests({
    required List<String> requested,
    required ShadcnConfig config,
    required ComponentExistsInNamespace componentExists,
  }) async {
    final resolved = <AddRequest>[];

    final enabled = (config.registries ?? const <String, RegistryConfigEntry>{})
        .entries
        .where((entry) => entry.value.enabled)
        .map((entry) => entry.key)
        .toSet();
    final defaultNamespace = config.effectiveDefaultNamespace;
    if (enabled.isEmpty) {
      enabled.add(defaultNamespace);
    }

    for (final token in requested) {
      final qualified = parseQualifiedComponentRef(token);
      if (qualified != null) {
        resolved.add(
          AddRequest(
            namespace: qualified.namespace,
            componentId: qualified.componentId,
          ),
        );
        continue;
      }
      if (ComponentRefNormalizer.looksQualified(token)) {
        throw Exception(
          'Invalid component address "$token". Use @namespace/component',
        );
      }

      final candidates = <String>[];
      for (final namespace in enabled) {
        if (await componentExists(namespace, token)) {
          candidates.add(namespace);
        }
      }

      if (candidates.isEmpty) {
        throw Exception('Component "$token" not found.');
      }
      if (candidates.length > 1) {
        candidates.sort();
        throw Exception(
          'Component "$token" is ambiguous across registries (${candidates.join(', ')}). '
          'Use @namespace/component',
        );
      }
      resolved.add(
        AddRequest(namespace: candidates.first, componentId: token),
      );
    }

    return resolved;
  }
}
