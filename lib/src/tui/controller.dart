/// GUI state shared by every screen: the loaded project, the log, and the
/// background watcher.
library;

import 'dart:async';

import 'package:nocterm/nocterm.dart' hide Logger;

import '../config.dart';
import '../generate.dart';
import '../logger.dart';
import '../ops/project.dart';
import '../watch.dart';
import 'widgets/inputs.dart';

/// A [StringSink] that turns written text into log lines.
class _LineSink implements StringSink {
  _LineSink(this._emit);

  final void Function(String line) _emit;
  final _buffer = StringBuffer();

  @override
  void write(Object? object) {
    _buffer.write(object);
    final text = _buffer.toString();
    final lines = text.split('\n');
    _buffer
      ..clear()
      ..write(lines.removeLast());
    lines.forEach(_emit);
  }

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));
}

class GuiController extends ChangeNotifier {
  GuiController(this.rootPath) {
    reload();
  }

  final String rootPath;

  /// `null` when the project could not be loaded; see [loadError].
  Project? project;
  String? loadError;

  final List<Line> logs = [];
  static const _maxLogs = 500;

  ArbWatcher? _watcher;
  bool get watching => _watcher != null;
  bool _generating = false;

  /// Result of the last generation, for the header.
  GenerationResult? lastGeneration;

  late final Logger logger = Logger(
    level: LogLevel.verbose,
    out: _LineSink((l) => log(l)),
    err: _LineSink((l) => log(
          l,
          l.startsWith('error:')
              ? Tone.error
              : l.startsWith('warning:')
                  ? Tone.warning
                  : Tone.normal,
        )),
  );

  void log(String text, [Tone tone = Tone.normal]) {
    logs.add(Line(text, tone));
    if (logs.length > _maxLogs) logs.removeRange(0, logs.length - _maxLogs);
    notifyListeners();
  }

  void reload() {
    try {
      project = Project.load(rootPath);
      loadError = null;
    } on OpException catch (e) {
      project = null;
      loadError = e.message;
    }
    notifyListeners();
  }

  /// The loaded project, or an [OpException] explaining why there is none.
  Project get requireProject =>
      project ?? (throw OpException(loadError ?? 'The project is not loaded.'));

  /// Regenerate the Dart code. Generation output goes to the log; the level
  /// set in pubspec.yaml is ignored so the log panel always shows results.
  GenerationResult generate({bool force = false}) {
    _generating = true;
    final result = runGeneration(
      rootPath: rootPath,
      logger: logger,
      overrides: const ConfigOverrides(logLevel: LogLevel.warning),
      force: force,
    );
    _generating = false;
    lastGeneration = result;
    reload();
    return result;
  }

  Future<void> toggleWatch() async {
    final current = _watcher;
    if (current != null) {
      _watcher = null;
      await current.stop();
      log('Watch mode off.', Tone.muted);
      notifyListeners();
      return;
    }
    final watcher = ArbWatcher(
      rootPath: rootPath,
      patternOf: () => currentArbPattern(rootPath, null),
      onChange: () {
        if (_generating) return;
        log('Change detected; regenerating…', Tone.muted);
        generate();
      },
    );
    _watcher = watcher;
    await watcher.start();
    log('Watch mode on: ARB and pubspec.yaml changes regenerate the code.',
        Tone.accent);
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_watcher?.stop());
    _watcher = null;
    super.dispose();
  }
}
