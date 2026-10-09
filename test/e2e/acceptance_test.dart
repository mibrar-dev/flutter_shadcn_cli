@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/kit_registry.dart';

/// End-to-end acceptance gate (P5_CLI_PLAN.md §6.3).
///
/// Creates a real Flutter app, installs the kit registry through the CLI from
/// source, and asserts the acceptance conditions: `flutter analyze` is clean,
/// `remove` keeps the user-owned theme, `update --check` is a no-op, `doctor`
/// is clean and `theme apply` regenerates `app_theme.dart`.
///
/// Tagged `e2e` and skipped by default (it needs the Flutter SDK, the kit
/// checkout and a warm pub cache). Run it with:
///
/// ```bash
/// dart test -t e2e --run-skipped
/// ```
void main() {
  group('e2e acceptance', () {
    late Directory app;
    late String cliEntrypoint;
    late String registryRoot;
    String? unavailable;

    setUpAll(() async {
      final kit = findKitPackageRoot();
      if (kit == null) {
        unavailable = 'flutter_shadcn_kit not found (set SHADCN_KIT_ROOT)';
        return;
      }
      registryRoot = p.join(kit, 'lib', 'registry');
      if (!Directory(registryRoot).existsSync()) {
        unavailable = 'kit registry missing at $registryRoot';
        return;
      }
      if (!await _hasFlutter()) {
        unavailable = 'the flutter executable is not on PATH';
        return;
      }
      cliEntrypoint = p.join(await _packageRoot(), 'bin', 'shadcn.dart');
      app = Directory.systemTemp.createTempSync('shadcn_e2e_');
      final create = await Process.run(
        'flutter',
        ['create', '--empty', '--project-name', 'shadcn_e2e_app', app.path],
        workingDirectory: app.path,
      );
      if (create.exitCode != 0) {
        throw StateError(
          'flutter create failed (exit ${create.exitCode})\n'
          'stdout:\n${create.stdout}\nstderr:\n${create.stderr}',
        );
      }
    });

    tearDownAll(() {
      if (unavailable == null && app.existsSync()) {
        app.deleteSync(recursive: true);
      }
    });

    Future<ProcessResult> runCli(List<String> args) {
      return Process.run(
        Platform.resolvedExecutable,
        [cliEntrypoint, '--registry', registryRoot, ...args],
        workingDirectory: app.path,
        environment: {...Platform.environment, 'CI': 'true'},
      );
    }

    void expectSuccess(ProcessResult result, String label) {
      expect(
        result.exitCode,
        0,
        reason: '$label failed (exit ${result.exitCode})\n'
            'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
    }

    File file(String rel) => File(p.join(app.path, p.normalize(rel)));

    Map<String, dynamic> lock() =>
        jsonDecode(file('shadcn.lock').readAsStringSync())
            as Map<String, dynamic>;

    test('init -> add -> analyze -> remove -> update -> doctor -> theme',
        () async {
      if (unavailable != null) {
        markTestSkipped(unavailable!);
        return;
      }

      // ── init ──────────────────────────────────────────────────────────
      expectSuccess(await runCli(['init', '--yes']), 'init --yes');
      expect(file('.shadcn/config.json').existsSync(), isTrue);
      expect(file('shadcn.lock').existsSync(), isTrue);
      expect(file('lib/ui/shadcn/theme/app_theme.dart').existsSync(), isTrue);
      expect(file('lib/ui/shadcn/foundation/data.dart').existsSync(), isTrue);
      expect(file('lib/ui/shadcn/analysis_options.yaml').existsSync(), isTrue);
      expect(lock()['lockfileVersion'], 2);

      // ── add ───────────────────────────────────────────────────────────
      expectSuccess(
        await runCli(
          ['add', 'button', 'dialog', 'input', 'select', 'calendar'],
        ),
        'add button dialog input select calendar',
      );
      for (final id in ['button', 'dialog', 'input', 'select', 'calendar']) {
        expect(
          file('lib/ui/shadcn/components/$id/$id.dart').existsSync(),
          isTrue,
          reason: '$id.dart missing after add',
        );
      }
      final installed = lock()['components'] as List;
      final ids = [for (final entry in installed) (entry as Map)['id']];
      expect(ids, containsAll(['button', 'dialog', 'input', 'select']));

      // ── the acceptance gate ───────────────────────────────────────────
      final analyze = await Process.run(
        'flutter',
        ['analyze'],
        workingDirectory: app.path,
      );
      expectSuccess(analyze, 'flutter analyze');
      expect(analyze.stdout.toString(), contains('No issues found!'));

      // ── remove keeps the user-owned theme ─────────────────────────────
      expectSuccess(await runCli(['remove', 'dialog']), 'remove dialog');
      expect(
        file('lib/ui/shadcn/components/dialog/dialog.dart').existsSync(),
        isFalse,
      );
      expect(
        file('lib/ui/shadcn/components/dialog/dialog_theme.dart').existsSync(),
        isTrue,
      );

      // ── update --check is a no-op ─────────────────────────────────────
      expectSuccess(await runCli(['update', '--check']), 'update --check');

      // ── doctor is clean ───────────────────────────────────────────────
      expectSuccess(await runCli(['doctor']), 'doctor');

      // ── theme apply regenerates app_theme.dart ────────────────────────
      expectSuccess(
        await runCli(['theme', 'apply', 'tangerine', '--refresh']),
        'theme apply tangerine --refresh',
      );
      expect(
        file('lib/ui/shadcn/theme/app_theme.dart').readAsStringSync(),
        contains('buildTangerineTheme'),
      );
      expect((lock()['theme'] as Map)['id'], 'tangerine');
    }, timeout: const Timeout(Duration(minutes: 30)));
  }, timeout: const Timeout(Duration(minutes: 30)));
}

Future<bool> _hasFlutter() async {
  try {
    final result = await Process.run('flutter', ['--version']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Future<String> _packageRoot() async {
  final packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_shadcn_cli/flutter_shadcn_cli.dart'),
  );
  if (packageUri == null) {
    throw StateError('Could not resolve the flutter_shadcn_cli package root');
  }
  return p.dirname(p.dirname(File.fromUri(packageUri).path));
}
