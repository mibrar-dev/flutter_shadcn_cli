import 'package:flutter_shadcn_cli/src/infrastructure/resolver/filesystem_guard.dart';
import 'package:test/test.dart';

void main() {
  group('FilesystemGuard', () {
    test('throws typed exception when target escapes root', () {
      const guard = FilesystemGuard();

      expect(
        () => guard.assertWithinRoot(
          root: '/tmp/project',
          targetPath: '/tmp/project-other/file.dart',
        ),
        throwsA(isA<PathEscapeException>()),
      );
    });
  });
}
