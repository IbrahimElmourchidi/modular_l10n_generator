import 'dart:io';

import 'config.dart';

/// Level-aware console output. Results go to stdout, problems to stderr.
class Logger {
  Logger({this.level = LogLevel.warning, StringSink? out, StringSink? err})
      : _out = out ?? stdout,
        _err = err ?? stderr;

  LogLevel level;
  final StringSink _out;
  final StringSink _err;

  bool _allows(LogLevel wanted) => level.index >= wanted.index;

  void error(String message) {
    if (_allows(LogLevel.error)) _err.writeln('error: $message');
  }

  void warn(String message) {
    if (_allows(LogLevel.warning)) _err.writeln('warning: $message');
  }

  /// A result line, shown at the default level.
  void summary(String message) {
    if (_allows(LogLevel.warning)) _out.writeln(message);
  }

  /// Progress detail, shown only when verbose.
  void verbose(String message) {
    if (_allows(LogLevel.verbose)) _out.writeln(message);
  }
}
