/// Raised when `shadcn.lock` exists but is not a readable lockfileVersion 2
/// document: bad JSON, a v1 lock, or a structurally invalid entry.
///
/// Extends [FormatException] so callers that already surface format errors for
/// user supplied files keep working.
class LockFileException extends FormatException {
  /// Project relative path of the lock file that failed to parse.
  final String path;

  LockFileException(String message, this.path, [Object? source, int? offset])
      : super(message, source, offset);

  @override
  String toString() => 'Invalid $path: $message';
}
