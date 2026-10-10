class ExitCodes {
  static const int success = 0;
  static const int usage = 2;
  static const int unknown = 1;

  static const int registryNotFound = 10;
  static const int schemaInvalid = 20;
  static const int componentMissing = 30;
  static const int fileMissing = 31;
  static const int networkError = 40;
  static const int offlineUnavailable = 41;
  static const int validationFailed = 50;
  static const int configInvalid = 60;
  static const int ioError = 70;

  /// `theme apply` refused to overwrite a user-owned `app_theme.dart` that
  /// drifted from `shadcn.lock`, and no `--refresh` was given. Distinct from
  /// [validationFailed] (50): nothing is invalid, the CLI is protecting a file
  /// the user owns, and `--refresh` resolves it.
  static const int themeDrift = 80;
}
