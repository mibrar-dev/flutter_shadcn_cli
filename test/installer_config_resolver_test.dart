import 'package:flutter_shadcn_cli/src/application/services/installer/installer_config_resolver.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:flutter_shadcn_cli/src/registry.dart';
import 'package:test/test.dart';

void main() {
  group('InstallerConfigResolver', () {
    test('uses registry defaults when project config has no paths', () {
      final resolver = InstallerConfigResolver(
        registry: _registry(
          defaults: {
            'installPath': 'lib/custom/components',
            'sharedPath': 'lib/custom/shared',
          },
        ),
      );

      expect(
          resolver.installPath(const ShadcnConfig()), 'lib/custom/components');
      expect(resolver.sharedPath(const ShadcnConfig()), 'lib/custom/shared');
    });

    test('uses namespace registry config before top-level config', () {
      final resolver = InstallerConfigResolver(
        registry: _registry(),
        registryNamespace: 'alt',
      );
      final config = const ShadcnConfig(
        installPath: 'lib/ui/default',
        sharedPath: 'lib/ui/default/shared',
        registries: {
          'alt': RegistryConfigEntry(
            installPath: 'lib/ui/alt',
            sharedPath: 'lib/ui/alt/shared',
          ),
        },
      );

      expect(resolver.installPath(config), 'lib/ui/alt');
      expect(resolver.sharedPath(config), 'lib/ui/alt/shared');
    });

    test('explicit overrides win and expand aliases', () {
      final resolver = InstallerConfigResolver(
        registry: _registry(),
        installPathOverride: '@ui/components',
        sharedPathOverride: '@ui/shared',
      );
      final config = const ShadcnConfig(
        pathAliases: {'ui': 'lib/app/ui'},
      );

      expect(resolver.installPath(config), 'lib/app/ui/components');
      expect(resolver.sharedPath(config), 'lib/app/ui/shared');
    });
  });
}

Registry _registry({Map<String, String> defaults = const {}}) {
  return Registry(
    {
      'defaults': defaults,
      'components': const [],
    },
    RegistryLocation.local('.'),
    RegistryLocation.local('.'),
  );
}
