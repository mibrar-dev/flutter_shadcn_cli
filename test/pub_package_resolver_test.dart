import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/installer/pub_package_resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _RecordingRunner implements PubCommandRunner {
  final List<String> pubGets = [];
  final List<List<String>> pubAdds = [];

  @override
  Future<void> pubGet(String projectRoot) async => pubGets.add(projectRoot);

  @override
  Future<void> pubAdd(String projectRoot, Iterable<String> packages) async {
    pubAdds.add(packages.toList());
  }
}

void main() {
  late Directory temp;
  late _RecordingRunner runner;
  late PubPackageResolver resolver;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pub_resolver_');
    runner = _RecordingRunner();
    resolver = PubPackageResolver(projectRoot: temp.path, runner: runner);
  });

  tearDown(() => temp.delete(recursive: true));

  void writePubspec(String content) =>
      File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync(content);

  test('reports a missing package and can apply it', () async {
    writePubspec('name: app\n\ndependencies:\n  flutter:\n    sdk: flutter\n');
    final plan = await resolver.plan(const [
      PubPackageRequirement(name: 'intl', constraint: '^0.20.2'),
    ]);
    expect(plan.missing.map((p) => p.name), ['intl']);
    expect(plan.present, isEmpty);
    expect(plan.hasChanges, isTrue);

    await resolver.apply(plan);
    final written = File(p.join(temp.path, 'pubspec.yaml')).readAsStringSync();
    expect(written, contains('intl: ^0.20.2'));
    expect(runner.pubGets, [temp.path]);
  });

  test('keeps a compatible existing constraint', () async {
    writePubspec('name: app\n\ndependencies:\n  intl: ^0.20.2\n');
    final plan = await resolver.plan(const [
      PubPackageRequirement(name: 'intl', constraint: '^0.20.2'),
    ]);
    expect(plan.missing, isEmpty);
    expect(plan.present, ['intl']);
    expect(plan.hasChanges, isFalse);
    await resolver.apply(plan);
    expect(runner.pubGets, isEmpty);
  });

  test('does not overwrite an incompatible constraint', () async {
    writePubspec('name: app\n\ndependencies:\n  intl: ^0.17.0\n');
    final plan = await resolver.plan(const [
      PubPackageRequirement(name: 'intl', constraint: '^0.20.2'),
    ]);
    expect(plan.missing, isEmpty);
    expect(plan.conflicts, hasLength(1));
    expect(plan.hasChanges, isFalse);
    await resolver.apply(plan);
    expect(
      File(p.join(temp.path, 'pubspec.yaml')).readAsStringSync(),
      contains('intl: ^0.17.0'),
    );
    expect(runner.pubGets, isEmpty);
  });

  test('formats an sdk package as a nested sdk entry', () async {
    writePubspec('name: app\n');
    final plan = await resolver.plan(const [
      PubPackageRequirement(name: 'flutter_localizations', sdk: true),
    ]);
    expect(plan.missing.map((p) => p.name), ['flutter_localizations']);
    await resolver.apply(plan);
    final written = File(p.join(temp.path, 'pubspec.yaml')).readAsStringSync();
    expect(written, contains('flutter_localizations:'));
    expect(written, contains('sdk: flutter'));
  });

  test('treats a missing pubspec as all-missing and cannot apply', () async {
    final plan = await resolver.plan(const [
      PubPackageRequirement(name: 'intl'),
    ]);
    expect(plan.missing.map((p) => p.name), ['intl']);
    expect(plan.hasChanges, isFalse);
    await resolver.apply(plan);
    expect(runner.pubGets, isEmpty);
  });

  test('can skip pub get', () async {
    writePubspec('name: app\n');
    final plan = await resolver.plan(const [
      PubPackageRequirement(name: 'intl'),
    ]);
    await resolver.apply(plan, runPubGet: false);
    expect(runner.pubGets, isEmpty);
  });
}
