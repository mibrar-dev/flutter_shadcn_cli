import 'dart:io';

class CliLogger {
  final bool verbose;
  final bool useColor;
  final void Function(String) _writeLine;
  final void Function(String) _writeStderrLine;

  CliLogger({
    this.verbose = false,
    bool? useColor,
    void Function(String)? writeLine,
    void Function(String)? writeStderrLine,
  })  : useColor = useColor ?? stdout.supportsAnsiEscapes,
        _writeLine = writeLine ?? ((message) => stdout.writeln(message)),
        _writeStderrLine =
            writeStderrLine ?? ((message) => stderr.writeln(message));

  static const _reset = '\u001b[0m';
  static const _bold = '\u001b[1m';
  static const _dim = '\u001b[2m';
  static const _cyan = '\u001b[36m';
  static const _green = '\u001b[32m';
  static const _yellow = '\u001b[33m';
  static const _red = '\u001b[31m';

  void header(String message) => _write(_style('✨ $message', _bold + _cyan));

  void action(String message) => _write(_style('• $message', _cyan));

  void progress(String message) => _write(_style('... $message', _dim));

  void success(String message) => _write(_style('✓ $message', _green));

  void warn(String message) => _writeStderr(_style('! $message', _yellow));

  void error(String message) => _writeStderr(_style('✗ $message', _red));

  void info(String message) => _write(message);

  void detail(String message) {
    if (verbose) {
      _writeStderr(_style('  ↳ $message', _dim));
    }
  }

  /// Explicit stderr variants. Schema/index validation warnings during
  /// `--json` runs must never pollute STDOUT (which must stay parseable
  /// JSON), so loaders call these directly.
  void warnToStderr(String message) =>
      _writeStderr(_style('! $message', _yellow));

  void errorToStderr(String message) =>
      _writeStderr(_style('✗ $message', _red));

  void section(String title) => _write(_style('\n$title', _bold));

  String _style(String message, String style) {
    if (!useColor) {
      return message;
    }
    return '$style$message$_reset';
  }

  void _write(String message) {
    _writeLine(message);
  }

  void _writeStderr(String message) {
    _writeStderrLine(message);
  }
}
