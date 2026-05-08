import 'package:flutter_shadcn_cli/src/application/services/pubspec/pubspec_change_planner.dart';
import 'package:test/test.dart';

void main() {
  group('PubspecChangePlanner', () {
    const planner = PubspecChangePlanner();

    test('keeps an existing dependency with the same constraint', () {
      final result = planner.planAddDependencies(
        const [
          'name: app',
          'dependencies:',
          '  # consumer note',
          '  intl: ^0.20.0',
        ],
        const {'intl': '^0.20.0'},
      );

      expect(result.added, isEmpty);
      expect(result.kept, {'intl': '^0.20.0'});
      expect(result.conflicts, isEmpty);
      expect(result.lines, contains('  # consumer note'));
    });

    test('reports conflicting existing dependency constraints', () {
      final result = planner.planAddDependencies(
        const [
          'name: app',
          'dependencies:',
          '  intl: ^0.19.0',
        ],
        const {'intl': '^0.20.0'},
      );

      expect(result.added, isEmpty);
      expect(result.kept, isEmpty);
      expect(result.conflicts, hasLength(1));
      expect(result.conflicts.single.package, 'intl');
      expect(result.conflicts.single.existing, '^0.19.0');
      expect(result.conflicts.single.requested, '^0.20.0');
    });

    test('preserves and compares map-shaped dependencies structurally', () {
      final result = planner.planAddDependencies(
        const [
          'name: app',
          'dependencies:',
          '  local_pkg:',
          '    path: ../local_pkg',
        ],
        const {
          'local_pkg': {'path': '../local_pkg'},
        },
      );

      expect(result.added, isEmpty);
      expect(result.kept, {
        'local_pkg': {'path': '../local_pkg'},
      });
      expect(result.conflicts, isEmpty);
      expect(result.lines, contains('    path: ../local_pkg'));
    });

    test('normalizes quoted scalar dependencies before comparison', () {
      final result = planner.planAddDependencies(
        const [
          'name: app',
          'dependencies:',
          '  intl: "^0.20.0"',
        ],
        const {'intl': '^0.20.0'},
      );

      expect(result.kept, {'intl': '^0.20.0'});
      expect(result.conflicts, isEmpty);
    });

    test('compares nested git dependency maps structurally', () {
      final result = planner.planAddDependencies(
        const [
          'name: app',
          'dependencies:',
          '  foo:',
          '    git:',
          '      url: https://example.com/foo.git',
          '      ref: main',
        ],
        const {
          'foo': {
            'git': {
              'url': 'https://example.com/foo.git',
              'ref': 'main',
            },
          },
        },
      );

      expect(result.kept, isNotEmpty);
      expect(result.conflicts, isEmpty);
    });

    test('removes only owned dependency entries and preserves comments', () {
      final result = planner.planRemoveDependencies(
        const [
          'name: app',
          'dependencies:',
          '  # keep this comment',
          '  intl: ^0.20.0',
          '  path:',
          '    sdk: flutter',
          'dev_dependencies:',
          '  lints: ^6.1.0',
        ],
        const {'intl'},
      );

      expect(result.removed, ['intl']);
      expect(result.lines, contains('  # keep this comment'));
      expect(result.lines, isNot(contains('  intl: ^0.20.0')));
      expect(result.lines, contains('  path:'));
      expect(result.lines, contains('dev_dependencies:'));
    });

    test('preserves comments that belong to the next dependency', () {
      final result = planner.planRemoveDependencies(
        const [
          'name: app',
          'dependencies:',
          '  foo: ^1.0.0',
          '  # bar is pinned for API compatibility',
          '  bar: ^2.0.0',
        ],
        const {'foo'},
      );

      expect(result.removed, ['foo']);
      expect(
        result.lines,
        contains('  # bar is pinned for API compatibility'),
      );
      expect(result.lines, contains('  bar: ^2.0.0'));
    });

    test('removes map-shaped dependency entries with internal comments', () {
      final result = planner.planRemoveDependencies(
        const [
          'name: app',
          'dependencies:',
          '  foo:',
          '    git:',
          '      # pinned to the generated API version',
          '      url: https://example.com/foo.git',
          '      ref: main',
          '  bar: ^2.0.0',
        ],
        const {'foo'},
      );

      expect(result.removed, ['foo']);
      expect(
        result.lines,
        isNot(contains('      # pinned to the generated API version')),
      );
      expect(result.lines, isNot(contains('      ref: main')));
      expect(result.lines, contains('  bar: ^2.0.0'));
    });

    test('detects dependency already present in opposite section', () {
      final result = planner.planAddDependencies(
        const [
          'name: app',
          'dependencies:',
          '  foo: ^1.0.0',
        ],
        const {'foo': '^1.0.0'},
        section: 'dev_dependencies',
      );

      expect(result.added, isEmpty);
      expect(result.conflicts, hasLength(1));
      expect(result.conflicts.single.package, 'foo');
    });

    test('detects runtime dependency already present in dev dependencies', () {
      final result = planner.planAddDependencies(
        const [
          'name: app',
          'dependencies:',
          '  flutter:',
          '    sdk: flutter',
          'dev_dependencies:',
          '  foo: ^1.0.0',
        ],
        const {'foo': '^1.0.0'},
      );

      expect(result.added, isEmpty);
      expect(result.conflicts, hasLength(1));
      expect(result.conflicts.single.package, 'foo');
    });
  });
}
