import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/installer_file_install_part.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/application/services/manifest_closure.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_pub_runner.dart';

/// Block installs (P6-B2): `add login-01` resolves a block like a component,
/// copies it into `blocks/<id>/` with its whole closure, and records it in
/// `shadcn.lock` v2.
void main() {
  final fixtureRoot = p.absolute('test/fixtures/registry_v2');
  final manifestPath = p.join(fixtureRoot, 'registry.json');
  late RegistryManifest manifest;
  late String manifestSha;
  late Directory temp;
  late FakePubCommandRunner runner;

  setUpAll(() async {
    manifest = RegistryManifest.fromJson(
      jsonDecode(File(manifestPath).readAsStringSync()) as Map<String, dynamic>,
    );
    manifestSha = await FileHashing.ofFile(File(manifestPath));
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('installer_blocks_');
    runner = FakePubCommandRunner();
  });

  tearDown(() => temp.delete(recursive: true));

  Installer buildInstaller({RegistryFileReader? reader}) => Installer(
        manifest: manifest,
        projectRoot: temp.path,
        reader: reader ?? DirectoryRegistryFileReader(fixtureRoot),
        pubRunner: runner,
        manifestSha256: manifestSha,
      );

  bool exists(String target) => File(p.join(temp.path, target)).existsSync();

  List<String> tree() => [
        for (final entity in Directory(temp.path).listSync(recursive: true))
          if (entity is File)
            p.relative(entity.path, from: temp.path).replaceAll('\\', '/'),
      ]..sort();

  group('plan', () {
    test('resolves a block and its component closure', () async {
      final plan =
          await buildInstaller().plan(const [], blockIds: ['login-01']);
      expect(plan.blocks, ['login-01']);
      expect(plan.components, ['button', 'input']);
      expect(plan.foundation, ['data', 'gap']);
      expect(plan.theme, ['color_tokens', 'theme']);
      expect(plan.primitives, ['clickable', 'form_core']);
      expect(
        plan.files.map((file) => file.target),
        contains('lib/ui/shadcn/blocks/login-01/login_01.dart'),
      );
      expect(tree(), isEmpty);
    });

    test('copies every file a multi-file block declares', () async {
      final plan =
          await buildInstaller().plan(const [], blockIds: ['dashboard-01']);
      expect(
        plan.files.map((file) => file.target),
        containsAll([
          'lib/ui/shadcn/blocks/dashboard-01/dashboard_01.dart',
          'lib/ui/shadcn/blocks/dashboard-01/dashboard_01_table.dart',
        ]),
      );
      // The block's README is documentation: never copied into the app.
      expect(
        plan.files.map((file) => file.source),
        isNot(contains('blocks/dashboard-01/README.md')),
      );
    });

    test('an unknown block id is refused', () async {
      await expectLater(
        buildInstaller().plan(const [], blockIds: ['nope-01']),
        throwsA(
          isA<ManifestClosureException>()
              .having((e) => e.kind, 'kind', 'block')
              .having((e) => e.id, 'id', 'nope-01'),
        ),
      );
    });
  });

  group('add', () {
    test('writes the block tree and records the block in the lock', () async {
      final report =
          await buildInstaller().add(const [], blockIds: ['login-01']);
      expect(report.applied, isTrue);
      expect(exists('lib/ui/shadcn/blocks/login-01/login_01.dart'), isTrue);
      expect(exists('lib/ui/shadcn/components/button/button.dart'), isTrue);
      expect(exists('lib/ui/shadcn/components/input/input.dart'), isTrue);
      expect(exists('lib/ui/shadcn/foundation/data.dart'), isTrue);
      expect(exists('lib/ui/shadcn/theme/theme.dart'), isTrue);

      final lock = await ShadcnLockRepository(temp.path).load();
      expect(lock.blockIds, ['login-01']);
      // The block owns no user-editable file, so everything it recorded is
      // updatable.
      expect(lock.userOwnedPaths, isNot(contains('lib/ui/shadcn/blocks/')));
      final block = lock.blockFor('login-01')!;
      expect(block.paths, ['lib/ui/shadcn/blocks/login-01/login_01.dart']);
      expect(block.deps.components, ['button', 'input']);
      expect(
        block.files.values.single,
        isNotEmpty,
        reason: 'the lock records the block hash',
      );
      expect(lock.ownerOf('lib/ui/shadcn/blocks/login-01/login_01.dart'),
          'login-01');
    });

    test('re-adding a block keeps its hash and writes nothing twice', () async {
      await buildInstaller().add(const [], blockIds: ['login-01']);
      final before = tree();
      final report =
          await buildInstaller().add(const [], blockIds: ['login-01']);
      expect(report.written, isEmpty, reason: 'identical files are skipped');
      expect(tree(), before);
      final lock = await ShadcnLockRepository(temp.path).load();
      expect(lock.blockIds, ['login-01']);
    });

    test('an edited block file survives a plain re-add', () async {
      await buildInstaller().add(const [], blockIds: ['login-01']);
      final file = File(
        p.join(temp.path, 'lib/ui/shadcn/blocks/login-01/login_01.dart'),
      );
      file.writeAsStringSync('// locally edited\n');

      await buildInstaller().add(const [], blockIds: ['login-01']);
      expect(file.readAsStringSync(), '// locally edited\n');
    });

    test('a block never claims a public symbol (single-owner preflight)',
        () async {
      // button and input both install alongside the block, and the preflight
      // still passes: a block declares no api.
      await expectLater(
        buildInstaller().add(const [], blockIds: ['login-01']),
        completes,
      );
    });
  });

  group('import guard', () {
    test('accepts a block that imports components and a sibling part',
        () async {
      final reader = DirectoryRegistryFileReader(fixtureRoot);
      final sources = await InstallerFileInstaller(
        projectRoot: temp.path,
        installRoot: manifest.install.root,
        reader: reader,
      ).readAll(const [
        'blocks/login-01/login_01.dart',
        'blocks/dashboard-01/dashboard_01.dart',
      ]);
      final installer = InstallerFileInstaller(
        projectRoot: temp.path,
        installRoot: manifest.install.root,
        reader: reader,
      );
      expect(
        () => installer.assertImportGuard({
          for (final entry in sources.entries)
            entry.key: decodeRegistryText(entry.value),
        }),
        returnsNormally,
      );
    });

    test('rejects a block import that escapes the layout', () {
      final installer = InstallerFileInstaller(
        projectRoot: temp.path,
        installRoot: manifest.install.root,
        reader: const DirectoryRegistryFileReader('.'),
      );
      expect(
        () => installer.assertImportGuard({
          'blocks/login-01/login_01.dart':
              "import '../../../lib/somewhere_else.dart';\n",
        }),
        throwsA(isA<ImportGuardException>()),
      );
      // A block→block import stays inside `blocks/`, so the depth guard lets it
      // through: layer direction (a block may not import another block) is
      // enforced by the kit's `check_layers` `block-imports` rule, not here.
      expect(
        () => installer.assertImportGuard({
          'blocks/login-01/login_01.dart':
              "import '../dashboard-01/dashboard_01.dart';\n",
        }),
        returnsNormally,
      );
    });
  });

  group('remove', () {
    test('removes a block and every file it owns', () async {
      await buildInstaller().add(const [], blockIds: ['login-01']);
      final report = await buildInstaller().remove(['login-01']);
      expect(report.removedBlocks, ['login-01']);
      expect(report.removed, isEmpty);
      expect(exists('lib/ui/shadcn/blocks/login-01/login_01.dart'), isFalse);
      // The components it assembled stay installed.
      expect(exists('lib/ui/shadcn/components/button/button.dart'), isTrue);
      final lock = await ShadcnLockRepository(temp.path).load();
      expect(lock.blockIds, isEmpty);
    });

    test('refuses to remove a component a block still needs', () async {
      await buildInstaller().add(const [], blockIds: ['login-01']);
      final report = await buildInstaller().remove(['input']);
      expect(report.refused, ['input']);
      expect(report.dependents['input'], ['login-01']);
      expect(exists('lib/ui/shadcn/components/input/input.dart'), isTrue);

      final forced = await buildInstaller().remove(['input'], force: true);
      expect(forced.removed, ['input']);
      expect(exists('lib/ui/shadcn/components/input/input.dart'), isFalse);
    });

    test('removing a block orphans nothing but its own files', () async {
      await buildInstaller().add(const [], blockIds: ['dashboard-01']);
      final report = await buildInstaller().remove(['dashboard-01']);
      expect(report.removedBlocks, ['dashboard-01']);
      expect(
        report.deletedFiles,
        containsAll([
          'lib/ui/shadcn/blocks/dashboard-01/dashboard_01.dart',
          'lib/ui/shadcn/blocks/dashboard-01/dashboard_01_table.dart',
        ]),
      );
      // form_core is only needed by the block's components, which stay.
      expect(
          exists('lib/ui/shadcn/primitives/form_core/form_core.dart'), isTrue);
    });
  });
}
