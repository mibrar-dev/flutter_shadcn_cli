// Golden test: the CLI's `renderAppTheme` must produce byte-for-byte the same
// `app_theme.dart` as the kit's `tool/rearch/gen_app_theme.dart`.
//
// The kit runs the same generator in-process for all 42 presets
// (`flutter_shadcn_kit/test/registry/themes/gen_app_theme_test.dart`); this
// suite shells out to the real tool so a divergence in either implementation
// fails here rather than silently in a user's app.
//
// The kit checkout is located relative to this package
// (`../shadcn_flutter_kit/flutter_shadcn_kit`) and can be overridden with
// `SHADCN_KIT_ROOT`. Without it the suite skips with a printed reason instead
// of failing, so the CLI package stays testable on its own.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/theme/app_theme_generator.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/app_theme_values.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/kit_registry.dart';

/// The presets the brief requires: `vercel` (the `init --yes` default, §9.2)
/// plus two others.
const List<String> goldenPresets = <String>[
  'vercel',
  'claude',
  'modern-minimal',
];

/// Both import forms matter: the CLI writes sibling-relative imports into the
/// install root, while the kit's own verification may use a `package:` URI.
const List<String> goldenThemeImports = <String>[
  'theme.dart',
  'package:flutter_shadcn_kit/registry/theme/theme.dart',
];

void main() {
  final kitRoot = findKitPackageRoot();

  group('renderAppTheme matches the kit generator', () {
    if (kitRoot == null) {
      test(
        'kit generator unavailable',
        () {},
        skip: 'shadcn_flutter_kit checkout not found (set SHADCN_KIT_ROOT)',
      );
      return;
    }
    final generator = p.join(kitRoot, 'tool', 'rearch', 'gen_app_theme.dart');

    for (final presetId in goldenPresets) {
      for (final themeImport in goldenThemeImports) {
        test('$presetId ($themeImport)', () {
          final presetJson =
              p.join(kitRoot, 'lib', 'registry', 'themes', '$presetId.json');
          expect(File(presetJson).existsSync(), isTrue,
              reason: 'missing preset $presetJson');

          final expected = _runKitGenerator(
            generator,
            presetJson,
            themeImport: themeImport,
          );
          final actual = renderAppTheme(
            _readPreset(presetJson),
            themeImport: themeImport,
          );
          expect(actual, expected);
        });
      }
    }

    test('every kit preset renders and keeps its shape', () {
      final themesDir = Directory(p.join(kitRoot, 'lib', 'registry', 'themes'));
      final presets = themesDir
          .listSync()
          .whereType<File>()
          .map((file) => p.basename(file.path))
          .where((name) => name.endsWith('.json'))
          .where(
            (name) => name != 'themes.schema.json' && name != 'index.json',
          )
          .toList()
        ..sort();
      expect(presets, isNotEmpty);

      final rendered = <String, String>{};
      for (final name in presets) {
        final values = _readPreset(p.join(themesDir.path, name));
        rendered[values.id] = renderAppTheme(values);
      }
      expect(rendered.length, presets.length);

      final vercel = rendered['vercel']!;
      expect(vercel, contains('const ShadcnColors vercelLightColors'));
      expect(vercel, contains('ShadcnThemeData buildVercelTheme'));
      expect(vercel, contains('fontSans:'));

      final withoutFonts = <String>[
        for (final entry in rendered.entries)
          if (!entry.value.contains('fontSans:')) entry.key,
      ];
      expect(withoutFonts, isNotEmpty,
          reason: 'expected a preset without a fonts block');
      for (final id in withoutFonts) {
        expect(rendered[id], isNot(contains('ShadcnFonts')));
      }
    });

    test('the package-import form is dart format clean', () {
      final dir = Directory.systemTemp.createTempSync('app_theme_format_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final written = <String>[];
      for (final presetId in goldenPresets) {
        final file = File(p.join(dir.path, '${presetId}_app_theme.dart'))
          ..writeAsStringSync(
            renderAppTheme(
              _readPreset(
                p.join(kitRoot, 'lib', 'registry', 'themes', '$presetId.json'),
              ),
              themeImport: goldenThemeImports.last,
            ),
          );
        written.add(file.path);
      }
      final result = Process.runSync(
        Platform.resolvedExecutable,
        <String>[
          'format',
          '--output=none',
          '--set-exit-if-changed',
          ...written
        ],
      );
      expect(
        result.exitCode,
        0,
        reason: 'dart format would change the generated files:\n'
            '${result.stdout}${result.stderr}',
      );
    });

    // Known, deliberate divergence (see the batch report): with the
    // sibling-relative imports an installed app needs, `dart format` (tall
    // style) keeps `package:` and relative imports in separate groups and
    // wants one blank line between them. The shared emitter omits it so the
    // CLI output stays byte-identical to the kit's generator; the kit only
    // ever emits `package:` imports, so it never hits this. Fixing it is a
    // one-line change in the kit generator plus the same change here.
    test('the relative-import form only misses the import-group blank line',
        () {
      final dir = Directory.systemTemp.createTempSync('app_theme_format_rel_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = renderAppTheme(
        _readPreset(
            p.join(kitRoot, 'lib', 'registry', 'themes', 'vercel.json')),
      );
      final file = File(p.join(dir.path, 'vercel_app_theme.dart'))
        ..writeAsStringSync(source);
      final formatted = Process.runSync(
        Platform.resolvedExecutable,
        <String>['format', '--output=show', file.path],
      );
      final formattedText =
          '${(formatted.stdout as String).split('\n').where((line) => !line.startsWith('Formatted ')).join('\n').trimRight()}\n';
      expect(
        formattedText,
        source.replaceFirst(
          "import 'package:flutter/widgets.dart';\n",
          "import 'package:flutter/widgets.dart';\n\n",
        ),
      );
    });
  });
}

AppThemeValues _readPreset(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync()) as Map;
  return AppThemeValues.fromJson(
    decoded.map((key, value) => MapEntry(key.toString(), value)),
  );
}

/// Runs the kit tool in a child process. The tool only needs `dart:*` plus one
/// relative import, so no `pub get` is required inside the kit.
String _runKitGenerator(
  String generator,
  String presetJson, {
  required String themeImport,
}) {
  final dir = Directory.systemTemp.createTempSync('app_theme_kit_');
  final out = p.join(dir.path, 'app_theme.dart');
  try {
    final result = Process.runSync(
      Platform.resolvedExecutable,
      <String>[generator, presetJson, out, '--theme-import', themeImport],
    );
    if (result.exitCode != 0) {
      fail(
        'kit generator failed (${result.exitCode}): '
        '${result.stdout}${result.stderr}',
      );
    }
    return File(out).readAsStringSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}
