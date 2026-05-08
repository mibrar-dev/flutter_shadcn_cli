import 'package:flutter_shadcn_cli/src/application/services/installer/installer_file_selection_policy.dart';
import 'package:flutter_shadcn_cli/src/config.dart';
import 'package:test/test.dart';

void main() {
  group('InstallerFileSelectionPolicy', () {
    test('installs non-optional files by default', () {
      const policy = InstallerFileSelectionPolicy();

      expect(policy.shouldInstallFile('lib/ui/button.dart', null), isTrue);
    });

    test('uses default readme meta and preview behavior', () {
      const policy = InstallerFileSelectionPolicy();

      expect(policy.shouldInstallFile('README.md', null), isFalse);
      expect(policy.shouldInstallFile('meta.json', null), isTrue);
      expect(policy.shouldInstallFile('button_preview.dart', null), isFalse);
    });

    test('explicit include override wins before config excludes', () {
      const policy = InstallerFileSelectionPolicy(
        includeFileKindsOverride: {'preview'},
      );
      const config = ShadcnConfig(excludeFiles: ['preview']);

      expect(
        policy.shouldInstallFile('components/button_preview.dart', config),
        isTrue,
      );
    });

    test('explicit exclude override skips matching optional files', () {
      const policy = InstallerFileSelectionPolicy(
        excludeFileKindsOverride: {'meta'},
      );
      const config = ShadcnConfig(includeMeta: true);

      expect(policy.shouldInstallFile('components/meta.json', config), isFalse);
    });

    test('normalizes configured file kind aliases', () {
      const policy = InstallerFileSelectionPolicy();
      const config = ShadcnConfig(includeFiles: ['docs', 'previews']);

      expect(policy.shouldInstallFile('README.md', config), isTrue);
      expect(policy.shouldInstallFile('button_preview.dart', config), isTrue);
      expect(policy.shouldInstallFile('meta.json', config), isFalse);
    });

    test('uses namespace registry file options before top-level options', () {
      const policy = InstallerFileSelectionPolicy(registryNamespace: 'alt');
      const config = ShadcnConfig(
        includePreview: true,
        registries: {
          'alt': RegistryConfigEntry(includePreview: false),
        },
      );

      expect(policy.shouldInstallFile('button_preview.dart', config), isFalse);
    });
  });
}
