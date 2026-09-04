import 'dart:io';

import 'package:flutter_shadcn_cli/src/core/utils/path_utils.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('path utils', () {
    test('throws typed exception when project root cannot be found', () {
      final tempDir = Directory.systemTemp.createTempSync('path_utils_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final nested = Directory(p.join(tempDir.path, 'a', 'b'))
        ..createSync(recursive: true);

      expect(
        () => findProjectRootFrom(nested.path),
        throwsA(isA<ProjectRootNotFoundException>()),
      );
    });
  });
}
