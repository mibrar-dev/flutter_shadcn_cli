import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/reset/global_reset_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('GlobalResetService', () {
    late Directory tempHome;

    setUp(() {
      tempHome = Directory.systemTemp.createTempSync('global_reset_home_');
    });

    tearDown(() {
      if (tempHome.existsSync()) {
        tempHome.deleteSync(recursive: true);
      }
    });

    test('deletes only CLI-owned home-directory state', () async {
      final cliHome = Directory(p.join(tempHome.path, '.flutter_shadcn'))
        ..createSync(recursive: true);
      Directory(p.join(cliHome.path, 'cache', 'registry'))
          .createSync(recursive: true);
      Directory(p.join(cliHome.path, 'crashes')).createSync(recursive: true);
      Directory(p.join(cliHome.path, 'project-resets', 'abc123'))
          .createSync(recursive: true);
      Directory(p.join(cliHome.path, 'local-files'))
          .createSync(recursive: true);
      File(p.join(cliHome.path, 'cache', 'registry', 'index.json'))
          .writeAsStringSync('{}');
      File(p.join(cliHome.path, 'crashes', 'latest.log'))
          .writeAsStringSync('boom');
      File(p.join(cliHome.path, 'project-resets', 'abc123', 'manifest.json'))
          .writeAsStringSync('{}');
      File(p.join(cliHome.path, 'local-files', 'notes.txt'))
          .writeAsStringSync('keep');

      final executable =
          File(p.join(tempHome.path, '.pub-cache', 'bin', 'flutter_shadcn'))
            ..createSync(recursive: true)
            ..writeAsStringSync('#!/bin/sh');
      final projectFile =
          File(p.join(tempHome.path, 'workspace', '.shadcn', 'config.json'))
            ..createSync(recursive: true)
            ..writeAsStringSync('{}');

      final service = GlobalResetService(homeDirectory: tempHome.path);

      final result = await service.reset();

      expect(Directory(p.join(cliHome.path, 'cache')).existsSync(), isFalse);
      expect(Directory(p.join(cliHome.path, 'crashes')).existsSync(), isFalse);
      expect(Directory(p.join(cliHome.path, 'project-resets')).existsSync(),
          isFalse);
      expect(
        Directory(p.join(cliHome.path, 'local-files')).existsSync(),
        isTrue,
      );
      expect(executable.existsSync(), isTrue);
      expect(projectFile.existsSync(), isTrue);
      expect(
        result.deletedRelativePaths,
        containsAll(['cache', 'crashes', 'project-resets']),
      );
    });
  });
}
