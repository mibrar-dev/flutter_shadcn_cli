// Shared harness for the theme service tests: a temp project plus the
// checked-in v2 registry fixture (1 foundation unit, 1 theme unit, 1
// primitive, 1 component and two real presets, `vercel` and `claude`).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_registry_source.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_service.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The registry fixture checked in next to this test.
String get fixtureRegistryRoot =>
    p.join(Directory.current.path, 'test', 'fixtures', 'theme_registry_v2');

/// A [ThemeRegistrySource] over the fixture, reading straight from disk.
ThemeRegistrySource fixtureSource() {
  return ThemeRegistrySource.overReader(
    (relPath) async {
      final file = File(p.join(fixtureRegistryRoot, relPath));
      return file.existsSync() ? file.readAsString() : null;
    },
    registryRoot: fixtureRegistryRoot,
    describe: (rel) => p.join(fixtureRegistryRoot, rel),
  );
}

/// Decoded `themes/<id>.json` from the fixture.
Map<String, dynamic> fixturePresetJson(String id) =>
    jsonDecode(File(p.join(fixtureRegistryRoot, 'themes', '$id.json'))
        .readAsStringSync()) as Map<String, dynamic>;

/// Per-test scaffolding: a temp project root, a logger and a `ThemeService`
/// factory bound to the fixture manifest.
class ThemeTestHarness {
  ThemeTestHarness(this.prefix) {
    temp = Directory.systemTemp.createTempSync(prefix);
    projectRoot = p.join(temp.path, 'app');
    Directory(projectRoot).createSync(recursive: true);
  }

  /// Registers teardown with the enclosing test group.
  factory ThemeTestHarness.create(String prefix) {
    final harness = ThemeTestHarness(prefix);
    addTearDown(() {
      if (harness.temp.existsSync()) {
        harness.temp.deleteSync(recursive: true);
      }
    });
    return harness;
  }

  final String prefix;
  late final Directory temp;
  late final String projectRoot;
  final CliLogger logger = CliLogger(useColor: false);

  /// The fixture manifest, loaded once per suite.
  late final RegistryManifest manifest;

  /// Binds the already-loaded fixture manifest to this harness.
  void useManifest(RegistryManifest value) => manifest = value;

  /// A service over the fixture, optionally with a different install root or
  /// a different registry source.
  ThemeService service({
    String? installRoot,
    ThemeRegistrySource? source,
  }) {
    return ThemeService(
      projectRoot: projectRoot,
      source: source ?? fixtureSource(),
      manifest: manifest,
      installRootOverride: installRoot,
      logger: logger,
    );
  }

  /// `<projectRoot>/<installRoot>/theme/app_theme.dart`.
  File themeFile([String installRoot = 'lib/ui/shadcn']) =>
      File(p.join(projectRoot, installRoot, 'theme', 'app_theme.dart'));

  /// The lock as written on disk.
  ShadcnLock lock() => ShadcnLockRepository(projectRoot)
      .parse(File(p.join(projectRoot, 'shadcn.lock')).readAsStringSync());
}
