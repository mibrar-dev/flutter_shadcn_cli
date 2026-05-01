import 'package:flutter_shadcn_cli/src/infrastructure/resolver/v1/resolver_v1_exception.dart';
import 'package:path/path.dart' as p;

class InitPathMapper {
  static String mapCopyFileDestination({
    required String filePath,
    String? base,
    String? destBase,
  }) {
    if ((base == null) != (destBase == null)) {
      throw ResolverV1Exception('base and destBase must be provided together');
    }
    if (base == null) {
      return filePath;
    }

    final expectedPrefix = '$base/';
    final stripped = filePath.startsWith(expectedPrefix)
        ? filePath.substring(expectedPrefix.length)
        : filePath;
    if (stripped.isEmpty) {
      throw ResolverV1Exception('file path cannot map to empty destination');
    }
    return p.posix.join(destBase!, stripped);
  }

  static String mapSourcePath({
    required String filePath,
    String? base,
  }) {
    if (base == null) {
      return filePath;
    }
    final expectedPrefix = '$base/';
    if (filePath.startsWith(expectedPrefix)) {
      return filePath;
    }
    return p.posix.join(base, filePath);
  }

  static String mapCopyDirDestination({
    required String filePath,
    required String from,
    required String to,
    String? base,
    String? destBase,
  }) {
    if ((base == null) != (destBase == null)) {
      throw ResolverV1Exception('base and destBase must be provided together');
    }

    final normalizedFrom = from.replaceAll('\\', '/');
    final sourcePath =
        base == null ? filePath : mapSourcePath(filePath: filePath, base: base);
    final filePrefix =
        base == null ? '$normalizedFrom/' : '$base/$normalizedFrom/';
    if (!sourcePath.startsWith(filePrefix)) {
      throw ResolverV1Exception(
        'copyDir source file is outside expected prefix: $filePath',
      );
    }

    final relativeTail = sourcePath.substring(filePrefix.length);
    if (relativeTail.isEmpty) {
      throw ResolverV1Exception('copyDir source file must point to a file');
    }
    var destination = p.posix.join(to, relativeTail);
    if (destBase != null) {
      destination = p.posix.join(destBase, destination);
    }
    return p.posix.normalize(destination);
  }
}
