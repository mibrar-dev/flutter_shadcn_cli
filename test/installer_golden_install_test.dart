import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_file_install_part.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_lock_part.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_pub_runner.dart';

/// Golden install of `test/fixtures/registry_v2/` into a temp project.
///
/// Asserts the exact file tree (byte-for-byte) and the exact `shadcn.lock`
/// content (byte-for-byte) for `add button`.
void main() {
  final fixtureRoot = p.absolute('test/fixtures/registry_v2');
  final manifestPath = p.join(fixtureRoot, 'registry.json');
  const installRoot = 'lib/ui/shadcn';

  late RegistryManifest manifest;
  late String manifestSha;
  late Directory temp;

  setUpAll(() async {
    manifest = RegistryManifest.fromJson(
      jsonDecode(File(manifestPath).readAsStringSync()) as Map<String, dynamic>,
    );
    manifestSha = await FileHashing.ofFile(File(manifestPath));
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('golden_install_');
  });

  tearDown(() => temp.delete(recursive: true));

  Future<String> sha(String relPath) =>
      FileHashing.ofFile(File(p.join(fixtureRoot, relPath)));

  String target(String relPath) => p.posix.join(installRoot, relPath);

  test('add button produces the golden tree and lock', () async {
    final installer = Installer(
      manifest: manifest,
      projectRoot: temp.path,
      reader: DirectoryRegistryFileReader(fixtureRoot),
      pubRunner: FakePubCommandRunner(),
      manifestSha256: manifestSha,
    );

    final report = await installer.add(['button']);
    expect(report.applied, isTrue);

    // ── Golden file tree ────────────────────────────────────────────────
    final expectedSources = <String>[
      'components/button/button.dart',
      'components/button/button_style.dart',
      'components/button/button_theme.dart',
      'foundation/data.dart',
      'foundation/gap.dart',
      'primitives/clickable.dart',
      'theme/color_tokens.dart',
      'theme/color_utils.dart',
      'theme/theme.dart',
    ];
    final expectedTree = <String>[
      for (final source in expectedSources) target(source),
      'shadcn.lock',
    ]..sort();
    final actualTree = [
      for (final entity in Directory(temp.path).listSync(recursive: true))
        if (entity is File)
          p.relative(entity.path, from: temp.path).replaceAll('\\', '/'),
    ]..sort();
    expect(actualTree, expectedTree);

    // Every copied file is byte-for-byte the registry source.
    for (final source in expectedSources) {
      expect(
        File(p.join(temp.path, target(source))).readAsBytesSync(),
        File(p.join(fixtureRoot, source)).readAsBytesSync(),
        reason: source,
      );
    }

    // ── Golden lock content ─────────────────────────────────────────────
    final button = manifest.components['button']!;
    final expectedLock = ShadcnLock(
      registry: ShadcnLockRegistry(
        name: manifest.registry.name,
        ref: manifest.registry.ref,
        manifestSha256: manifestSha,
        generatedAt: manifest.registry.generatedAt,
      ),
      installRoot: installRoot,
    ).mergeLayer(
      LockLayer.foundation,
      units: {'data', 'gap'},
      files: {
        target('foundation/data.dart'): await sha('foundation/data.dart'),
        target('foundation/gap.dart'): await sha('foundation/gap.dart'),
      },
    ).mergeLayer(
      LockLayer.theme,
      units: {'color_tokens', 'theme'},
      files: {
        target('theme/theme.dart'): await sha('theme/theme.dart'),
        target('theme/color_tokens.dart'): await sha('theme/color_tokens.dart'),
        target('theme/color_utils.dart'): await sha('theme/color_utils.dart'),
      },
    ).mergeLayer(
      LockLayer.primitives,
      units: {'clickable'},
      files: {
        target('primitives/clickable.dart'):
            await sha('primitives/clickable.dart'),
      },
    ).upsertComponent(
      ShadcnLockComponent(
        id: 'button',
        files: {
          target('components/button/button.dart'):
              await sha('components/button/button.dart'),
          target('components/button/button_style.dart'):
              await sha('components/button/button_style.dart'),
        },
        userOwned: {
          target('components/button/button_theme.dart'):
              await sha('components/button/button_theme.dart'),
        },
        deps: const LockComponentDeps(
          foundation: ['data', 'gap'],
          theme: ['color_tokens', 'theme'],
          primitives: ['clickable'],
        ),
        api: lockApiFor(button.api),
      ),
    );

    final expectedLockText =
        '${const JsonEncoder.withIndent('  ').convert(expectedLock.toJson())}\n';
    expect(
      File(p.join(temp.path, 'shadcn.lock')).readAsStringSync(),
      expectedLockText,
    );

    // The saved lock also round-trips through the repository.
    final loaded = await ShadcnLockRepository(temp.path).load();
    expect(loaded.componentIds, ['button']);
    expect(loaded.registry.manifestSha256, manifestSha);
  });
}
