import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/installer.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/pub_package_resolver.dart';
import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_manifest_loader.dart';
import 'package:flutter_shadcn_cli/src/application/services/registry_source.dart';
import 'package:flutter_shadcn_cli/src/application/services/update/update_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/v2_registry_fixture.dart';

class _NoopPubRunner implements PubCommandRunner {
  const _NoopPubRunner();

  @override
  Future<void> pubAdd(String projectRoot, Iterable<String> packages) async {}

  @override
  Future<void> pubGet(String projectRoot) async {}
}

void main() {
  group('UpdateService', () {
    late V2RegistryFixture fixture;
    late Directory project;
    const installRoot = 'lib/ui/shadcn';
    late RegistrySource source;

    setUp(() async {
      fixture = V2RegistryFixture.create();
      project = Directory.systemTemp.createTempSync('update_service_app_');
      File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync(
        'name: update_app\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
      );
      source = LocalRegistrySource(fixture.root);
      final loaded = await RegistryManifestLoader(source).load();
      final installer = Installer(
        manifest: loaded.manifest,
        projectRoot: project.path,
        reader: RegistrySourceFileReader(source),
        installRoot: installRoot,
        manifestSha256: loaded.sha256,
        pubRunner: const _NoopPubRunner(),
      );
      await installer.add(['button']);
    });

    tearDown(() {
      fixture.dispose();
      project.deleteSync(recursive: true);
    });

    Future<UpdateReport> update({bool check = false}) async {
      final loaded = await RegistryManifestLoader(source).load();
      return UpdateService(
        manifest: loaded.manifest,
        reader: RegistrySourceFileReader(source),
        projectRoot: project.path,
        installRoot: installRoot,
        manifestSha256: loaded.sha256,
      ).run(check: check);
    }

    String target(String rel) => p.join(installRoot, rel);
    String disk(String rel) =>
        File(p.join(project.path, p.normalize(target(rel)))).readAsStringSync();

    test('is a no-op when everything matches', () async {
      final report = await update();
      expect(report.updated, isEmpty);
      expect(report.modified, isEmpty);
      expect(report.removedUpstream, isEmpty);
      expect(report.needsAttention, isFalse);
    });

    test('overwrites an unchanged file with the registry bytes', () async {
      fixture.writeRegistryFile(
        'components/button/button.dart',
        'class Button { final v = 2; }\n',
      );
      final report = await update();
      expect(report.updated, contains(target('components/button/button.dart')));
      expect(disk('components/button/button.dart'), contains('v = 2'));

      final lock = await ShadcnLockRepository(project.path).load();
      final button = lock.componentFor('button')!;
      expect(
        button.files[target('components/button/button.dart')],
        FileHashing.ofText('class Button { final v = 2; }\n'),
      );
    });

    test('skips a locally modified file and reports it', () async {
      File(p.join(project.path, target('components/button/button.dart')))
          .writeAsStringSync('class Button { final mine = true; }\n');
      fixture.writeRegistryFile(
        'components/button/button.dart',
        'class Button { final v = 3; }\n',
      );
      final report = await update();
      expect(
          report.modified, contains(target('components/button/button.dart')));
      expect(disk('components/button/button.dart'), contains('mine = true'));
      expect(report.updated,
          isNot(contains(target('components/button/button.dart'))));
    });

    test('never touches a user-owned theme file', () async {
      File(p.join(project.path, target('components/button/button_theme.dart')))
          .writeAsStringSync('class ButtonTheme { final mine = true; }\n');
      final report = await update();
      expect(
        report.updated,
        isNot(contains(target('components/button/button_theme.dart'))),
      );
      expect(
        report.modified,
        isNot(contains(target('components/button/button_theme.dart'))),
      );
      expect(
          disk('components/button/button_theme.dart'), contains('mine = true'));
    });

    test('reports a file removed from the manifest and leaves it', () async {
      final manifest = V2RegistryFixture.buildManifest(fileHashes: {
        for (final entry in const [
          'foundation/data.dart',
          'theme/color_tokens.dart',
          'primitives/clickable.dart',
        ])
          entry: FileHashing.ofText(fixture.read(entry)),
      })
        ..['components'] = <String, dynamic>{};
      fixture.writeManifest(manifest);
      final report = await update();
      expect(report.removedUpstream, isNotEmpty);
      expect(
        File(p.join(project.path, target('components/button/button.dart')))
            .existsSync(),
        isTrue,
      );
    });

    test('restores a missing registry file', () async {
      final file =
          File(p.join(project.path, target('components/button/button.dart')))
            ..deleteSync();
      expect(file.existsSync(), isFalse);
      final report = await update();
      expect(report.missing, contains(target('components/button/button.dart')));
      expect(file.existsSync(), isTrue);
    });

    test('--check reports without writing', () async {
      fixture.writeRegistryFile(
        'components/button/button.dart',
        'class Button { final v = 9; }\n',
      );
      final report = await update(check: true);
      expect(report.applied, isFalse);
      expect(report.needsAttention, isTrue);
      expect(disk('components/button/button.dart'), isNot(contains('v = 9')));
    });
  });
}
