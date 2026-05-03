import 'dart:async';

import 'package:flutter_shadcn_cli/src/application/services/reset/global_reset_service.dart';
import 'package:flutter_shadcn_cli/src/application/services/reset/project_reset_service.dart';
import 'package:flutter_shadcn_cli/src/application/services/reset/reset_snapshot_manifest.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/project_command.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/commands/reset_command.dart';
import 'package:test/test.dart';

void main() {
  group('runResetCommand', () {
    test('cancels when confirmation is not yes', () async {
      final parser = buildCliParser();
      final args = parser.parse(['reset']);
      var called = false;

      final output = await _capturePrintAsync(() async {
        final exitCode = await runResetCommand(
          command: args.command!,
          service: const GlobalResetService(homeDirectory: '/tmp/home'),
          readConfirmation: () => 'n',
        );
        expect(exitCode, 0);
      });

      called = output.contains('Deleted global CLI state:');
      expect(called, isFalse);
      expect(output, contains('Cancelled.'));
    });

    test('runs global reset after confirmation', () async {
      final parser = buildCliParser();
      final args = parser.parse(['reset']);

      final output = await _capturePrintAsync(() async {
        final exitCode = await runResetCommand(
          command: args.command!,
          service: _FakeGlobalResetService(),
          readConfirmation: () => 'y',
        );
        expect(exitCode, 0);
      });

      expect(output, contains('Deleted global CLI state:'));
      expect(output, contains('~/.flutter_shadcn/cache'));
    });
  });

  group('runProjectCommand', () {
    test('project reset prints undo expiry', () async {
      final parser = buildCliParser();
      final args = parser.parse(['project', 'reset']);

      final output = await _capturePrintAsync(() async {
        final exitCode = await runProjectCommand(
          command: args.command!,
          resetProject: () async => ProjectResetResult(
            snapshot: _snapshot(),
            deletedDirectoryRoots: const ['.shadcn', 'lib/ui/shadcn'],
          ),
          undoProject: () async => ProjectResetUndoResult(snapshot: _snapshot()),
          refreshProject: () async => const ProjectRefreshOutput(
            regeneratedFiles: 0,
          ),
        );
        expect(exitCode, 0);
      });

      expect(output, contains('Removed CLI-managed project files:'));
      expect(output, contains('project reset --undo'));
    });

    test('project refresh reports regenerated files', () async {
      final parser = buildCliParser();
      final args = parser.parse(['project', 'refresh']);

      final output = await _capturePrintAsync(() async {
        final exitCode = await runProjectCommand(
          command: args.command!,
          resetProject: () async => ProjectResetResult(
            snapshot: _snapshot(),
            deletedDirectoryRoots: const [],
          ),
          undoProject: () async => ProjectResetUndoResult(snapshot: _snapshot()),
          refreshProject: () async => const ProjectRefreshOutput(
            regeneratedFiles: 2,
            repairedPaths: ['.shadcn/config.json', 'lib/ui/shadcn/shared/theme.dart'],
          ),
        );
        expect(exitCode, 0);
      });

      expect(output, contains('Regenerated 2 missing scaffolding files.'));
      expect(output, contains('.shadcn/config.json'));
    });
  });
}

class _FakeGlobalResetService extends GlobalResetService {
  _FakeGlobalResetService() : super(homeDirectory: '/tmp/home');

  @override
  Future<GlobalResetResult> reset() async {
    return const GlobalResetResult(deletedRelativePaths: ['cache']);
  }
}

ResetSnapshotManifest _snapshot() {
  return ResetSnapshotManifest(
    projectPath: '/tmp/project',
    createdAtUtc: DateTime.utc(2026, 5, 3, 12),
    expiresAtUtc: DateTime.utc(2026, 5, 4, 12),
    relativePaths: const ['.shadcn/config.json'],
    deletedDirectoryRoots: const ['.shadcn'],
  );
}

Future<String> _capturePrintAsync(Future<void> Function() callback) async {
  final lines = <String>[];
  await runZoned(
    callback,
    zoneSpecification: ZoneSpecification(
      print: (_, __, ___, line) => lines.add(line),
    ),
  );
  return lines.join('\n');
}
