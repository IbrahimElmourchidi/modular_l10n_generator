/// Watch mode: regenerate whenever a modular ARB file or `pubspec.yaml`
/// changes.
library;

import 'dart:async';
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'config.dart';
import 'module_scanner.dart';

/// Calls [onChange] after relevant file changes, debounced, and never more
/// than one run at a time.
///
/// A change that arrives while a run is in progress is folded into a single
/// follow-up run, so a burst of saves costs at most two generations.
class ArbWatcher {
  ArbWatcher({
    required this.rootPath,
    required this.patternOf,
    required this.onChange,
    this.trace,
    this.debounce = const Duration(milliseconds: 500),
  });

  final String rootPath;

  /// The ARB glob to match, re-read on every event so a `pubspec.yaml` edit
  /// takes effect without a restart.
  final String Function() patternOf;
  final FutureOr<void> Function() onChange;
  final void Function(String message)? trace;
  final Duration debounce;

  StreamSubscription<WatchEvent>? _subscription;
  Timer? _timer;
  bool _running = false;
  bool _pending = false;
  final _closed = Completer<void>();

  /// Start watching. Completes once the watcher is ready.
  Future<void> start() async {
    final watcher = DirectoryWatcher(rootPath);
    _subscription = watcher.events.listen(
      _handle,
      onError: (Object error) => trace?.call('File watcher error: $error'),
    );
    await watcher.ready;
  }

  /// Completes when [stop] is called.
  Future<void> get done => _closed.future;

  Future<void> stop() async {
    _timer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    if (!_closed.isCompleted) _closed.complete();
  }

  void _handle(WatchEvent event) {
    final removed = event.type == ChangeType.REMOVE;
    if (!isRelevant(event.path, removed: removed)) return;
    trace?.call('${event.type}: ${p.relative(event.path, from: rootPath)}');

    if (_running) {
      _pending = true;
      return;
    }
    _timer?.cancel();
    _timer = Timer(debounce, _run);
  }

  /// Whether a change to [path] should trigger a regeneration.
  bool isRelevant(String path, {bool removed = false}) {
    final relative = p.relative(path, from: rootPath);
    if (relative == 'pubspec.yaml') return true;
    if (p.extension(path) != '.arb') return false;
    if (isFlutterIntlFile(path)) return false;
    if (isInExcludedDirectory(path, rootPath)) return false;
    if (p.split(relative).any((s) => s.startsWith('.'))) return false;

    final posix = p.split(relative).join('/');
    if (!Glob(patternOf(), context: p.posix).matches(posix)) return false;

    // A deleted file can no longer be inspected; generated output (combined
    // ARBs, which carry no @@context) is not a source.
    return removed || _hasContext(path);
  }

  static bool _hasContext(String path) {
    try {
      final json = readJsonFile(path);
      return json is Map && json.containsKey('@@context');
    } on Object {
      return false;
    }
  }

  Future<void> _run() async {
    _timer = null;
    _running = true;
    try {
      await onChange();
    } on Object catch (error) {
      trace?.call('Regeneration failed: $error');
    } finally {
      _running = false;
      if (_pending) {
        _pending = false;
        _timer = Timer(debounce, _run);
      }
    }
  }
}

/// The ARB pattern currently configured for [rootPath], falling back to the
/// default when `pubspec.yaml` cannot be read mid-edit.
String currentArbPattern(String rootPath, String? override) {
  if (override != null) return override;
  try {
    return PubspecReader(rootPath).readConfig()?.arbFilePattern ??
        const L10nConfig().arbFilePattern;
  } on PubspecException {
    return const L10nConfig().arbFilePattern;
  } on FileSystemException {
    return const L10nConfig().arbFilePattern;
  }
}
