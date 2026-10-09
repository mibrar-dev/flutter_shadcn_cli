import 'package:flutter_shadcn_cli/src/application/services/theme/theme_models.dart';
import 'package:flutter_shadcn_cli/src/application/services/theme/theme_preset_prompt.dart';
import 'package:test/test.dart';

void main() {
  final presets = <ThemeCatalogEntry>[
    const ThemeCatalogEntry(
      id: 'claude',
      name: 'Claude',
      modes: <String>['light', 'dark'],
      file: 'themes/claude.json',
    ),
    const ThemeCatalogEntry(
      id: 'vercel',
      name: 'Vercel',
      modes: <String>['light', 'dark'],
      file: 'themes/vercel.json',
      isCurrent: true,
    ),
  ];

  Future<ThemeCatalogEntry?> answer(String? input) {
    final written = <String>[];
    return promptForThemePreset(
      presets,
      question: 'Theme number: ',
      readLine: () => input,
      write: (message) => written.add(message),
    );
  }

  test('returns null for an empty catalogue', () async {
    final chosen = await promptForThemePreset(
      const <ThemeCatalogEntry>[],
      question: 'Theme number: ',
      readLine: () => '1',
      write: (_) {},
    );
    expect(chosen, isNull);
  });

  test('accepts a 1-based index', () async {
    expect((await answer('1'))!.id, 'claude');
    expect((await answer('2'))!.id, 'vercel');
  });

  test('accepts an id or a display name, case insensitively', () async {
    expect((await answer('vercel'))!.id, 'vercel');
    expect((await answer('VERCEL'))!.id, 'vercel');
    expect((await answer('Claude'))!.id, 'claude');
  });

  test('returns null when the user skips or types nonsense', () async {
    expect(await answer(null), isNull);
    expect(await answer(''), isNull);
    expect(await answer('   '), isNull);
    expect(await answer('0'), isNull);
    expect(await answer('3'), isNull);
    expect(await answer('nope'), isNull);
  });

  test('lists every preset and marks the current one', () async {
    final written = <String>[];
    await promptForThemePreset(
      presets,
      question: 'Theme number: ',
      readLine: () => null,
      write: written.add,
    );
    expect(written.first, contains('1) Claude (claude)'));
    expect(written[1], contains('2) Vercel (vercel) (current)'));
    expect(written.last, 'Theme number: ');
  });
}
