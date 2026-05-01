import 'dart:io';
import 'dart:isolate';

import 'package:flutter_shadcn_cli/src/docs_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('generated command reference is up to date', () async {
    final root = await _packageRoot();
    final expected = renderCommandReferenceFiles();
    final commandsRoot = Directory(
      p.join(root, 'docs', 'reference', 'commands'),
    );
    final failures = <String>[];

    expected.forEach((relative, content) {
      final file = File(p.join(commandsRoot.path, relative));
      if (!file.existsSync()) {
        failures.add('Missing ${file.path}');
        return;
      }

      final actual = file.readAsStringSync().replaceAll('\r\n', '\n');
      final normalizedExpected = content.replaceAll('\r\n', '\n');
      if (actual != normalizedExpected) {
        failures.add('Stale ${file.path}');
      }
    });

    if (commandsRoot.existsSync()) {
      final expectedPaths = expected.keys.toSet();
      final actualPaths = commandsRoot
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => p.relative(file.path, from: commandsRoot.path))
          .toSet();
      for (final unexpected in actualPaths.difference(expectedPaths)) {
        failures.add('Unexpected ${p.join(commandsRoot.path, unexpected)}');
      }
    }

    expect(
      failures,
      isEmpty,
      reason: 'Generated command docs are stale.\n'
          'Run: dart run bin/shadcn.dart --advanced docs --generate',
    );
  });
}

Future<String> _packageRoot() async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_shadcn_cli/flutter_shadcn_cli.dart'),
  );
  if (uri == null) {
    throw StateError('Could not resolve package root');
  }
  return p.dirname(p.dirname(File.fromUri(uri).path));
}
