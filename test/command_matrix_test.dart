import 'dart:io';
import 'dart:isolate';

import 'package:flutter_shadcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_metadata.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Command matrix', () {
    late String packageRoot;
    late String cliEntrypoint;

    setUp(() async {
      packageRoot = await _packageRoot();
      cliEntrypoint = p.join(packageRoot, 'bin', 'shadcn.dart');
    });

    test('metadata and parser command sets match', () {
      final metadataIds = {
        for (final group in cliCommandMetadata)
          for (final command in group.commands) command.id,
      };
      final parserIds = buildCliParser().commands.keys.toSet();

      expect(parserIds.difference(metadataIds), isEmpty);
      expect(metadataIds.difference(parserIds), isEmpty);

      final aliases = {
        for (final group in cliCommandMetadata)
          for (final command in group.commands) ...command.aliases,
      };
      for (final alias in aliases) {
        expect(parserIds.contains(alias), isFalse, reason: alias);
      }
    });

    test('retired commands are gone from the parser', () {
      final parser = buildCliParser();
      for (final name in const ['assets', 'locale', 'platform', 'deps']) {
        expect(parser.commands.containsKey(name), isFalse, reason: name);
      }
    });

    test('all documented commands resolve with --help', () async {
      final commands = {
        for (final group in cliCommandMetadata)
          for (final command in group.commands) command.id,
      }.toList()
        ..sort();
      final advanced = {
        for (final group in cliCommandMetadata)
          for (final command in group.commands)
            if (command.advanced) command.id,
      };

      final failures = <String>[];
      for (final command in commands) {
        final result = await Process.run(
          Platform.resolvedExecutable,
          [
            cliEntrypoint,
            if (advanced.contains(command)) '--advanced',
            command,
            '--help',
          ],
          workingDirectory: packageRoot,
          environment: {...Platform.environment, 'CI': 'true'},
        );
        if (result.exitCode != 0) {
          failures.add(
            '$command => exit ${result.exitCode}\n'
            'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
          );
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n\n'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('registry selection commands resolve with --help', () async {
      for (final command in const ['registries', 'default', 'update']) {
        final result = await Process.run(
          Platform.resolvedExecutable,
          [cliEntrypoint, command, '--help'],
          workingDirectory: packageRoot,
          environment: {...Platform.environment, 'CI': 'true'},
        );
        expect(
          result.exitCode,
          0,
          reason: '$command help failed\n${result.stdout}\n${result.stderr}',
        );
      }
    });
  });
}

Future<String> _packageRoot() async {
  final packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_shadcn_cli/flutter_shadcn_cli.dart'),
  );
  if (packageUri == null) {
    throw Exception('Could not resolve package root');
  }
  return p.dirname(p.dirname(File.fromUri(packageUri).path));
}
