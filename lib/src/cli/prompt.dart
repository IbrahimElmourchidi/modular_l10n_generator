/// Line-based questions for subcommands run without all their flags.
library;

import 'dart:io';

/// Asks questions on the terminal. In a script or CI (no terminal on stdin),
/// [interactive] is false and commands must fail instead of waiting.
class Prompter {
  Prompter({Stdin? input, IOSink? output, bool? interactive})
      : _in = input ?? stdin,
        _out = output ?? stdout,
        interactive = interactive ?? (stdin.hasTerminal && stdout.hasTerminal);

  final Stdin _in;
  final IOSink _out;
  final bool interactive;

  String? _readLine() => _in.readLineSync();

  /// Ask for a line of text. An empty answer takes [defaultValue]; an answer
  /// [validate] rejects is asked again. Returns `null` on end of input.
  String? ask(
    String question, {
    String? defaultValue,
    String? Function(String value)? validate,
    bool allowEmpty = false,
  }) {
    while (true) {
      final hint = defaultValue == null || defaultValue.isEmpty
          ? ''
          : ' [$defaultValue]';
      _out.write('$question$hint: ');
      final line = _readLine();
      if (line == null) return null;
      var value = line.trim();
      if (value.isEmpty) value = defaultValue ?? '';
      if (value.isEmpty && !allowEmpty) {
        _out.writeln('  A value is required.');
        continue;
      }
      final error = value.isEmpty ? null : validate?.call(value);
      if (error != null) {
        _out.writeln('  $error');
        continue;
      }
      return value;
    }
  }

  /// Ask the user to pick one of [options] by number or by name.
  String? choose(String question, List<String> options,
      {String? defaultValue}) {
    _out.writeln(question);
    for (var i = 0; i < options.length; i++) {
      _out.writeln('  ${i + 1}) ${options[i]}');
    }
    return ask(
      'Choose 1-${options.length}',
      defaultValue: defaultValue,
      validate: (v) =>
          _pick(v, options) == null ? 'Not one of the choices.' : null,
    ).let((v) => _pick(v, options));
  }

  String? _pick(String value, List<String> options) {
    final n = int.tryParse(value);
    if (n != null && n >= 1 && n <= options.length) return options[n - 1];
    return options.contains(value) ? value : null;
  }

  /// Ask a yes/no question.
  bool confirm(String question, {bool defaultValue = false}) {
    final answer = ask(
      '$question (${defaultValue ? 'Y/n' : 'y/N'})',
      allowEmpty: true,
      validate: (v) =>
          RegExp(r'^(y|yes|n|no)$', caseSensitive: false).hasMatch(v)
              ? null
              : 'Answer y or n.',
    );
    if (answer == null || answer.isEmpty) return defaultValue;
    return answer.toLowerCase().startsWith('y');
  }
}

extension _Let<T> on T? {
  R? let<R>(R? Function(T value) f) => this == null ? null : f(this as T);
}
