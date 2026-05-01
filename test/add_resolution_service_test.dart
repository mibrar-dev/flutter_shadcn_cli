import 'package:flutter_shadcn_cli/src/application/services/add_resolution_service.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:test/test.dart';

void main() {
  group('AddResolutionService', () {
    const service = AddResolutionService();

    test('@namespace/component parses to canonical component ref', () {
      final ref =
          AddResolutionService.parseQualifiedComponentRef('@shadcn/button');

      expect(ref, isNotNull);
      expect(ref!.namespace, 'shadcn');
      expect(ref.componentId, 'button');
      expect(ref.canonical, '@shadcn/button');
    });

    test('namespace:component parses to the same canonical component ref', () {
      final atRef =
          AddResolutionService.parseQualifiedComponentRef('@shadcn/button');
      final colonRef =
          AddResolutionService.parseQualifiedComponentRef('shadcn:button');

      expect(colonRef, isNotNull);
      expect(colonRef!.namespace, atRef!.namespace);
      expect(colonRef.componentId, atRef.componentId);
      expect(colonRef.canonical, '@shadcn/button');
    });

    test('colon alias splits on the first colon only', () {
      final ref = AddResolutionService.parseQualifiedComponentRef(
        'shadcn:button:primary',
      );

      expect(ref, isNotNull);
      expect(ref!.namespace, 'shadcn');
      expect(ref.componentId, 'button:primary');
      expect(ref.canonical, '@shadcn/button:primary');
    });

    test('malformed component refs are rejected', () {
      for (final token in [
        '',
        '@',
        '@shadcn',
        '@shadcn/',
        '@/button',
        '@shadcn/button/extra',
        'shadcn:',
        ':button',
      ]) {
        expect(
          AddResolutionService.parseQualifiedComponentRef(token),
          isNull,
          reason: token,
        );
      }
    });

    test('qualified colon aliases resolve without probing raw input', () async {
      final probed = <String>[];
      final requests = await service.resolveAddRequests(
        requested: ['shadcn:button:primary'],
        config: _multiRegistryConfig(defaultNamespace: 'shadcn'),
        componentExists: (namespace, componentId) async {
          probed.add('$namespace/$componentId');
          return true;
        },
      );

      expect(requests, hasLength(1));
      expect(requests.single.namespace, 'shadcn');
      expect(requests.single.componentId, 'button:primary');
      expect(probed, isEmpty);
    });

    test('malformed qualified refs fail before component probing', () async {
      for (final token in [
        '@shadcn/button/extra',
        'shadcn:',
        ':button',
      ]) {
        final probed = <String>[];

        await expectLater(
          () => service.resolveAddRequests(
            requested: [token],
            config: _multiRegistryConfig(defaultNamespace: 'shadcn'),
            componentExists: (namespace, componentId) async {
              probed.add('$namespace/$componentId');
              return true;
            },
          ),
          throwsA(
            predicate(
              (Object error) =>
                  error.toString().contains('Invalid component address'),
              'invalid component address error',
            ),
          ),
        );
        expect(probed, isEmpty, reason: token);
      }
    });

    test('ambiguity errors show only canonical address form', () async {
      await expectLater(
        () => service.resolveAddRequests(
          requested: ['button'],
          config: _multiRegistryConfig(defaultNamespace: 'unknown'),
          componentExists: (namespace, componentId) async =>
              componentId == 'button' &&
              (namespace == 'shadcn' || namespace == 'alt'),
        ),
        throwsA(
          predicate(
            (Object error) {
              final message = error.toString();
              return message.contains('Use @namespace/component') &&
                  !message.contains('@<namespace>') &&
                  !message.contains('namespace:component') &&
                  !message.contains('namespace-qualified');
            },
            'canonical ambiguity error',
          ),
        ),
      );
    });
  });
}

ShadcnConfig _multiRegistryConfig({required String defaultNamespace}) {
  return ShadcnConfig(
    defaultNamespace: defaultNamespace,
    registries: {
      'shadcn': const RegistryConfigEntry(enabled: true),
      'alt': const RegistryConfigEntry(enabled: true),
    },
  );
}
