import 'package:flutter_shadcn_cli/src/application/services/pubspec/pubspec_editor.dart';
import 'package:test/test.dart';

void main() {
  group('PubspecEditor', () {
    test('appends dependencies, assets, and fonts without rewriting comments',
        () {
      final input = '''
name: sample_app

# Keep this dependency comment.
dependencies:
  flutter:
    sdk: flutter

flutter:
  # Keep this asset comment.
  uses-material-design: true
''';

      final editor = PubspecEditor(input);
      editor.addDependencies({'gap': '^3.0.1'});
      editor.addFlutterAssets(['assets/fonts/lucide.ttf']);
      editor.addFlutterFonts([
        PubspecFontFamily(
            'LucideIcons', [PubspecFontAsset('assets/fonts/lucide.ttf')]),
      ]);

      final output = editor.toString();
      expect(output, contains('# Keep this dependency comment.'));
      expect(output, contains('# Keep this asset comment.'));
      expect(output, contains('gap: ^3.0.1'));
      expect(output, contains('    - assets/fonts/lucide.ttf'));
      expect(output, contains('- family: LucideIcons'));
    });

    test('does not add dependencies that already exist', () {
      final input = '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
  gap: ^3.0.1
''';

      final editor = PubspecEditor(input);
      editor.addDependencies({'gap': '^3.0.1', 'new_dep': '^1.0.0'});

      final output = editor.toString();
      final occurrences = RegExp('gap:').allMatches(output).length;
      expect(occurrences, 1);
      expect(output, contains('new_dep: ^1.0.0'));
    });

    test('appends dependencies when section is missing', () {
      final input = '''
name: sample_app
version: 1.0.0
''';

      final editor = PubspecEditor(input);
      editor.addDependencies({'gap': '^3.0.1'});

      final output = editor.toString();
      expect(output, contains('dependencies:'));
      expect(output, contains('gap: ^3.0.1'));
    });

    test('appends flutter section when missing', () {
      final input = '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
''';

      final editor = PubspecEditor(input);
      editor.addFlutterAssets(['assets/logo.png']);

      final output = editor.toString();
      expect(output, contains('flutter:'));
      expect(output, contains('assets:'));
      expect(output, contains('- assets/logo.png'));
    });

    test('preserves blank lines and indentation', () {
      final input = '''
name: sample_app

description: A sample app

dependencies:
  flutter:
    sdk: flutter

  intl: ^0.19.0

flutter:
  uses-material-design: true
''';

      final editor = PubspecEditor(input);
      editor.addDependencies({'gap': '^3.0.1'});

      final output = editor.toString();
      expect(output, contains('\n\n'));
      expect(output, contains('  intl: ^0.19.0'));
      expect(output, contains('gap: ^3.0.1'));
    });

    test('does not duplicate assets that already exist', () {
      final input = '''
name: sample_app
flutter:
  assets:
    - assets/logo.png
''';

      final editor = PubspecEditor(input);
      editor.addFlutterAssets(['assets/logo.png', 'assets/icon.png']);

      final output = editor.toString();
      final assetOccurrences =
          RegExp(r'- assets/logo\.png').allMatches(output).length;
      expect(assetOccurrences, 1);
      expect(output, contains('- assets/icon.png'));
    });

    test('does not duplicate font families that already exist', () {
      final input = '''
name: sample_app
flutter:
  fonts:
    - family: LucideIcons
      fonts:
        - asset: assets/fonts/lucide.ttf
''';

      final editor = PubspecEditor(input);
      editor.addFlutterFonts([
        PubspecFontFamily(
            'LucideIcons', [PubspecFontAsset('assets/fonts/lucide.ttf')]),
        PubspecFontFamily(
            'GeistSans', [PubspecFontAsset('assets/fonts/geist.ttf')]),
      ]);

      final output = editor.toString();
      final familyOccurrences =
          RegExp(r'family: LucideIcons').allMatches(output).length;
      expect(familyOccurrences, 1);
      expect(output, contains('family: GeistSans'));
    });

    test('handles sdk-style dependency values', () {
      final input = '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
''';

      final editor = PubspecEditor(input);
      editor.addDependencies({
        'flutter_localizations': {'sdk': 'flutter'},
      });

      final output = editor.toString();
      expect(output, contains('flutter_localizations:'));
      expect(output, contains('sdk: flutter'));
    });

    test('rollback removes only added entries', () {
      final input = '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter

flutter:
  uses-material-design: true
''';

      final editor = PubspecEditor(input);
      editor.addDependencies({'gap': '^3.0.1'});
      editor.addFlutterAssets(['assets/fonts/lucide.ttf']);
      editor.addFlutterFonts([
        PubspecFontFamily(
            'LucideIcons', [PubspecFontAsset('assets/fonts/lucide.ttf')]),
      ]);

      final delta = editor.recordDelta();
      editor.rollbackDelta(delta);

      final output = editor.toString();
      expect(output.contains('gap:'), isFalse);
      expect(output.contains('assets/fonts/lucide.ttf'), isFalse);
      expect(output.contains('LucideIcons'), isFalse);
      expect(output, contains('flutter:'));
      expect(output, contains('sdk: flutter'));
    });

    test('preserves comments in flutter section', () {
      final input = '''
name: sample_app
flutter:
  # This is a comment about assets
  assets:
    - assets/existing.png
  # This is a comment about fonts
  fonts:
    - family: ExistingFont
      fonts:
        - asset: assets/existing_font.ttf
''';

      final editor = PubspecEditor(input);
      editor.addFlutterAssets(['assets/new.png']);
      editor.addFlutterFonts([
        PubspecFontFamily('NewFont', [PubspecFontAsset('assets/new_font.ttf')]),
      ]);

      final output = editor.toString();
      expect(output, contains('# This is a comment about assets'));
      expect(output, contains('# This is a comment about fonts'));
      expect(output, contains('- assets/existing.png'));
      expect(output, contains('- family: ExistingFont'));
    });

    test('handles dev_dependencies section', () {
      final input = '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  test: ^1.24.0
''';

      final editor = PubspecEditor(input);
      editor.addDevDependencies({'lints': '^6.1.0'});

      final output = editor.toString();
      expect(output, contains('lints: ^6.1.0'));
      expect(output, contains('test: ^1.24.0'));
    });

    test('handles multi-line dependency values', () {
      final input = '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
''';

      final editor = PubspecEditor(input);
      editor.addDependencies({
        'some_package': {
          'git': {'url': 'https://github.com/example/pkg.git'},
        },
      });

      final output = editor.toString();
      expect(output, contains('some_package:'));
      expect(output, contains('git:'));
      expect(output, contains('url:'));
    });
  });
}
