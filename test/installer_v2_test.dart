import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/dry_run_plan.dart';
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
  late FakePubCommandRunner runner;

  setUpAll(() async {
    manifest = RegistryManifest.fromJson(
      jsonDecode(File(manifestPath).readAsStringSync()) as Map<String, dynamic>,
    );
    manifestSha = await FileHashing.ofFile(File(manifestPath));
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('installer_v2_');
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

  List<String> tree() {
    final entries = Directory(temp.path).listSync(recursive: true);
    return [
      for (final entry in entries)
        if (entry is File)
          p.relative(entry.path, from: temp.path).replaceAll('\\', '/'),
    ]..sort();
  }

  group('plan', () {
    test('reports add actions without writing anything', () async {
      final plan = await buildInstaller().plan(['button']);
      expect(plan.components, ['button']);
      expect(plan.countOf(PlanAction.add), 9);
      expect(plan.countOf(PlanAction.keep), 0);
      expect(plan.packages.map((package) => package.name), ['intl']);
      expect(tree(), isEmpty);
    });

    test('includePreview is off by default and never finds a preview',
        () async {
      final plan =
          await buildInstaller().plan(['button'], includePreview: true);
      expect(plan.files.any((file) => file.source.endsWith('preview.dart')),
          isFalse);
    });

    test('marks a differing existing file as locally modified', () async {
      final target = File(
        p.join(temp.path, 'lib/ui/shadcn/foundation/data.dart'),
      );
      target.parent.createSync(recursive: true);
      target.writeAsStringSync('// user changed\n');
      final plan = await buildInstaller().plan(['button']);
      final entry = plan.files
          .firstWhere((file) => file.source == 'foundation/data.dart');
      expect(entry.action, PlanAction.skip);
      expect(entry.reason, 'locally modified');
    });

    test('overwrite turns the differing file into an update', () async {
      final target = File(
        p.join(temp.path, 'lib/ui/shadcn/foundation/data.dart'),
      );
      target.parent.createSync(recursive: true);
      target.writeAsStringSync('// user changed\n');
      final plan = await buildInstaller().plan(['button'], overwrite: true);
      final entry = plan.files
          .firstWhere((file) => file.source == 'foundation/data.dart');
      expect(entry.action, PlanAction.update);
    });
  });

  group('add', () {
    test('writes the tree and a lockfileVersion 2 lock', () async {
      final report = await buildInstaller().add(['button']);
      expect(report.applied, isTrue);
      expect(report.written, hasLength(9));

      final expected = [
        'lib/ui/shadcn/analysis_options.yaml',
        'lib/ui/shadcn/components/button/button.dart',
        'lib/ui/shadcn/components/button/button_style.dart',
        'lib/ui/shadcn/components/button/button_theme.dart',
        'lib/ui/shadcn/foundation/data.dart',
        'lib/ui/shadcn/foundation/gap.dart',
        'lib/ui/shadcn/primitives/clickable.dart',
        'lib/ui/shadcn/theme/color_tokens.dart',
        'lib/ui/shadcn/theme/color_utils.dart',
        'lib/ui/shadcn/theme/theme.dart',
        'shadcn.lock',
      ]..sort();
      expect(tree(), expected);

      final lock = await ShadcnLockRepository(temp.path).load();
      expect(lock.registry.manifestSha256, manifestSha);
      expect(lock.installRoot, 'lib/ui/shadcn');
      expect(lock.componentIds, ['button']);
      expect(lock.layerState(LockLayer.foundation).units, ['data', 'gap']);
      expect(lock.layerState(LockLayer.theme).units, ['color_tokens', 'theme']);
      expect(lock.layerState(LockLayer.primitives).units, ['clickable']);
      expect(lock.componentFor('button')!.userOwnedPaths, [
        'lib/ui/shadcn/components/button/button_theme.dart',
      ]);
    });

    test('dry-run writes nothing', () async {
      final report = await buildInstaller().add(['button'], dryRun: true);
      expect(report.applied, isFalse);
      expect(tree(), isEmpty);
    });

    test('re-adding keeps the user-owned file untouched', () async {
      await buildInstaller().add(['button']);
      final themeFile = File(
        p.join(temp.path, 'lib/ui/shadcn/components/button/button_theme.dart'),
      );
      themeFile.writeAsStringSync('// my custom theme\n');

      final plan = await buildInstaller().plan(['button']);
      final entry = plan.files.firstWhere(
        (file) => file.target.endsWith('button_theme.dart'),
      );
      expect(entry.action, PlanAction.keep);

      await buildInstaller().add(['button']);
      expect(themeFile.readAsStringSync(), '// my custom theme\n');
    });

    test('adds missing packages to pubspec and runs pub get', () async {
      File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync(
        'name: app\n\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );
      final report = await buildInstaller().add(['button']);
      expect(report.packagesAdded, ['intl']);
      expect(
        File(p.join(temp.path, 'pubspec.yaml')).readAsStringSync(),
        contains('intl: ^0.20.2'),
      );
      expect(runner.pubGets, [temp.path]);
    });
  });

  group('installCore / installAll', () {
    test('installCore writes the layer core and no component', () async {
      await buildInstaller().installCore();
      final lock = await ShadcnLockRepository(temp.path).load();
      expect(lock.componentIds, isEmpty);
      expect(lock.layerState(LockLayer.foundation).units, ['data', 'gap']);
      expect(lock.layerState(LockLayer.theme).units, ['color_tokens', 'theme']);
      expect(exists('lib/ui/shadcn/foundation/data.dart'), isTrue);
      expect(exists('lib/ui/shadcn/components/button/button.dart'), isFalse);
    });

    test('installAll installs every component', () async {
      await buildInstaller().installAll();
      final lock = await ShadcnLockRepository(temp.path).load();
      expect(lock.componentIds, ['button', 'input', 'text_area']);
    });
  });

  group('single-owner preflight', () {
    test('refuses two components that define the same symbol', () async {
      final json = jsonDecode(File(manifestPath).readAsStringSync())
          as Map<String, dynamic>;
      final components = json['components'] as Map<String, dynamic>;
      final input = Map<String, dynamic>.from(
        components['input'] as Map<String, dynamic>,
      );
      input['api'] = {
        'classes': ['Button'],
      };
      components['input'] = input;
      final conflicting = RegistryManifest.fromJson(json);

      final installer = Installer(
        manifest: conflicting,
        projectRoot: temp.path,
        reader: DirectoryRegistryFileReader(fixtureRoot),
        pubRunner: runner,
      );
      await expectLater(
        installer.add(['button', 'input']),
        throwsA(
          isA<SingleOwnerViolationException>().having(
            (e) => e.violations.keys,
            'violations',
            contains('Button'),
          ),
        ),
      );
      expect(tree(), isEmpty);
    });
  });

  group('import guard', () {
    test('aborts the install before writing when an import escapes', () async {
      final reader = _BadImportReader(fixtureRoot);
      await expectLater(
        buildInstaller(reader: reader).add(['button']),
        throwsA(isA<ImportGuardException>()),
      );
      expect(tree(), isEmpty);
    });
  });
}

/// Delegates to the fixture reader but rewrites button.dart with a bad import.
class _BadImportReader implements RegistryFileReader {
  _BadImportReader(String directory)
      : root = DirectoryRegistryFileReader(directory);

  final DirectoryRegistryFileReader root;

  @override
  Future<List<int>?> readBytes(String relPath) async {
    if (relPath == 'components/button/button.dart') {
      return utf8.encode("import '../../../foundation/data.dart';\n");
    }
    return root.readBytes(relPath);
  }

  @override
  Future<String?> readString(String relPath) async {
    final bytes = await readBytes(relPath);
    return bytes == null ? null : utf8.decode(bytes);
  }
}
