import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/lockfile/hashing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('FileHashing', () {
    test('matches the published sha256 vectors', () {
      expect(
        FileHashing.ofBytes(const <int>[]),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        FileHashing.ofText('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(FileHashing.ofText('abc'), FileHashing.ofBytes('abc'.codeUnits));
    });

    test('hashes a file the same way it hashes its bytes', () async {
      final temp = Directory.systemTemp.createTempSync('lock_hashing_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File(p.join(temp.path, 'button.dart'))
        ..writeAsStringSync('class Button {}');

      expect(await FileHashing.ofFile(file),
          FileHashing.ofText('class Button {}'));
      expect(await FileHashing.ofFileIfExists(file), isNotNull);
    });

    test('returns null for a missing file instead of throwing', () async {
      final temp = Directory.systemTemp.createTempSync('lock_hashing_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final missing = File(p.join(temp.path, 'nope.dart'));

      expect(await FileHashing.ofFileIfExists(missing), isNull);
    });

    test('ofFiles keys by callback and skips missing files', () async {
      final temp = Directory.systemTemp.createTempSync('lock_hashing_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final present = File(p.join(temp.path, 'a.dart'))..writeAsStringSync('a');
      final absent = File(p.join(temp.path, 'b.dart'));

      final digests = await FileHashing.ofFiles(
        [present, absent],
        keyOf: (file) => p.basename(file.path),
      );

      expect(digests.keys, ['a.dart']);
      expect(digests['a.dart'], FileHashing.ofText('a'));
    });

    test('recognises digests regardless of case and surrounding space', () {
      const digest =
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
      expect(FileHashing.isSha256(digest), isTrue);
      expect(FileHashing.isSha256(digest.toUpperCase()), isTrue);
      expect(FileHashing.isSha256(' $digest\n'), isTrue);
      expect(FileHashing.isSha256(''), isFalse);
      expect(FileHashing.isSha256(null), isFalse);
      expect(FileHashing.isSha256('abc'), isFalse);
      expect(FileHashing.isSha256('${digest}0'), isFalse);
      expect(FileHashing.normalize(' ${digest.toUpperCase()} '), digest);
      expect(() => FileHashing.normalize('nope'), throwsFormatException);
    });

    test('matches compares digests only', () {
      const digest =
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
      expect(FileHashing.matches(digest, digest.toUpperCase()), isTrue);
      expect(FileHashing.matches(digest, null), isFalse);
      expect(FileHashing.matches(null, digest), isFalse);
      expect(
        FileHashing.matches(digest, FileHashing.ofText('other')),
        isFalse,
      );
    });
  });
}
