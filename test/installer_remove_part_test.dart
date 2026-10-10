import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_file_install_part.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_pub_runner.dart';

void main() {
  final fixtureRoot = p.absolute('test/fixtures/registry_v2');
  final manifestPath = p.join(fixtureRoot, 'registry.json');
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
    temp = Directory.systemTemp.createTempSync('installer_remove_');
  });

  tearDown(() => temp.delete(recursive: true));

  Installer installer() => Installer(
        manifest: manifest,
        projectRoot: temp.path,
        reader: DirectoryRegistryFileReader(fixtureRoot),
        pubRunner: FakePubCommandRunner(),
        manifestSha256: manifestSha,
      );

  bool exists(String target) => File(p.join(temp.path, target)).existsSync();

  test('refuses to remove a component other installs still need', () async {
    await installer().add(['input', 'text_area']);
    final report = await installer().remove(['input']);
    expect(report.refused, ['input']);
    expect(report.removed, isEmpty);
    expect(report.dependents['input'], ['text_area']);
    expect(exists('lib/ui/shadcn/components/input/input.dart'), isTrue);
  });

  test('--force removes it anyway', () async {
    await installer().add(['input', 'text_area']);
    final report = await installer().remove(['input'], force: true);
    expect(report.removed, ['input']);
    expect(exists('lib/ui/shadcn/components/input/input.dart'), isFalse);
    expect(exists('lib/ui/shadcn/components/text_area/text_area.dart'), isTrue);
  });

  test('keeps user-owned theme files by default', () async {
    await installer().add(['button']);
    final report = await installer().remove(['button']);
    expect(report.removed, ['button']);
    expect(exists('lib/ui/shadcn/components/button/button.dart'), isFalse);
    expect(
        exists('lib/ui/shadcn/components/button/button_style.dart'), isFalse);
    expect(
      exists('lib/ui/shadcn/components/button/button_theme.dart'),
      isTrue,
    );
    expect(
      report.keptUserOwned,
      contains('lib/ui/shadcn/components/button/button_theme.dart'),
    );
  });

  test('purgeUserThemes deletes the user-owned theme file', () async {
    await installer().add(['button']);
    await installer().remove(['button'], purgeUserThemes: true);
    expect(
        exists('lib/ui/shadcn/components/button/button_theme.dart'), isFalse);
  });

  test('prunes primitive units no remaining install needs', () async {
    await installer().add(['input']);
    final before = await ShadcnLockRepository(temp.path).load();
    expect(
      before.layerState(LockLayer.primitives).units,
      ['clickable', 'form_core'],
    );

    await installer().remove(['input']);
    expect(exists('lib/ui/shadcn/primitives/clickable.dart'), isFalse);
    expect(
        exists('lib/ui/shadcn/primitives/form_core/form_core.dart'), isFalse);
    // The always-on foundation/theme core survives.
    expect(exists('lib/ui/shadcn/foundation/data.dart'), isTrue);
    expect(exists('lib/ui/shadcn/theme/theme.dart'), isTrue);

    final after = await ShadcnLockRepository(temp.path).load();
    expect(after.componentIds, isEmpty);
    expect(after.layerState(LockLayer.primitives).units, isEmpty);
    expect(after.layerState(LockLayer.primitives).files, isEmpty);
    expect(after.layerState(LockLayer.foundation).units, ['data', 'gap']);
  });

  test('keeps a primitive still needed by a remaining component', () async {
    await installer().add(['input', 'button']);
    await installer().remove(['button']);
    expect(exists('lib/ui/shadcn/primitives/clickable.dart'), isTrue);
    expect(exists('lib/ui/shadcn/primitives/form_core/form_core.dart'), isTrue);
  });

  test('dry-run reports without deleting', () async {
    await installer().add(['button']);
    final report = await installer().remove(['button'], dryRun: true);
    expect(report.applied, isFalse);
    expect(report.removed, ['button']);
    expect(exists('lib/ui/shadcn/components/button/button.dart'), isTrue);
  });

  test('skips components that are not installed', () async {
    final report = await installer().remove(['ghost']);
    expect(report.skipped, ['ghost']);
    expect(report.removed, isEmpty);
  });
}
