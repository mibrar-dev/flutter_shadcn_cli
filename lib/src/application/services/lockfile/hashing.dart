import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// sha256 helpers shared by the v2 lock file writer and the drift checks.
///
/// Every digest stored in `shadcn.lock` is the lowercase hex sha256 of the
/// exact bytes the CLI wrote to disk, so `update` and `doctor` can tell
/// "unchanged" from "locally modified" without re-reading the registry.
class FileHashing {
  const FileHashing._();

  static final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

  /// sha256 of [bytes].
  static String ofBytes(List<int> bytes) => sha256.convert(bytes).toString();

  /// sha256 of the utf8 encoding of [text].
  static String ofText(String text) => ofBytes(utf8.encode(text));

  /// sha256 of a file, streamed so large files stay cheap.
  static Future<String> ofFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// [ofFile], or `null` when the file does not exist.
  static Future<String?> ofFileIfExists(File file) async {
    if (!await file.exists()) {
      return null;
    }
    return ofFile(file);
  }

  /// sha256 of each existing file, keyed by [keyOf].
  static Future<Map<String, String>> ofFiles(
    Iterable<File> files, {
    required String Function(File file) keyOf,
  }) async {
    final digests = <String, String>{};
    for (final file in files) {
      final digest = await ofFileIfExists(file);
      if (digest != null) {
        digests[keyOf(file)] = digest;
      }
    }
    return digests;
  }

  /// True when [value] is a 64 character hex digest, case insensitive.
  static bool isSha256(String? value) {
    if (value == null) {
      return false;
    }
    final normalized = value.trim().toLowerCase();
    return _sha256.hasMatch(normalized);
  }

  /// Trimmed lowercase digest. Throws [FormatException] for anything that is
  /// not a sha256, which is how corrupt lock entries are rejected.
  static String normalize(String value) {
    final normalized = value.trim().toLowerCase();
    if (!_sha256.hasMatch(normalized)) {
      throw FormatException('Not a sha256 digest.', value);
    }
    return normalized;
  }

  /// True when both digests describe the same bytes.
  static bool matches(String? expected, String? actual) {
    if (expected == null || actual == null) {
      return false;
    }
    return normalize(expected) == normalize(actual);
  }
}
