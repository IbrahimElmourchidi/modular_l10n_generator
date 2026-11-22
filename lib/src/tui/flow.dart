/// Runs a GUI action as an async script of steps. Each `await` on a
/// [FlowContext] method shows one screen and resolves with the user's
/// answer; Esc cancels the whole action.
library;

import 'dart:async';

import 'package:nocterm/nocterm.dart' hide Logger;
import 'package:path/path.dart' as p;

import '../ops/project.dart';
import 'controller.dart';
import 'widgets/folder_picker.dart';
import 'widgets/inputs.dart';

/// Thrown by a step when the user presses Esc.
class FlowCancelled implements Exception {}

/// An action in the sidebar.
class GuiAction {
  const GuiAction({
    required this.group,
    required this.label,
    required this.description,
    required this.run,
    this.shortcut,
  });

  final String group;
  final String label;
  final String description;

  /// A single key that starts the action from the sidebar.
  final String? shortcut;
  final Future<void> Function(FlowContext f) run;
}

/// The steps an action can show.
class FlowContext {
  FlowContext._(this._view);

  final _FlowViewState _view;

  GuiController get app => _view.component.app;
  Project get project => app.requireProject;
  String get root => app.rootPath;
  String rel(String path) => p.relative(path, from: root);

  Future<T> _step<T>(String title, String? help,
      Component Function(void Function(T) done, VoidCallback cancel) build) {
    final completer = Completer<T>();
    void done(T value) {
      if (!completer.isCompleted) completer.complete(value);
    }

    void cancel() {
      if (!completer.isCompleted) completer.completeError(FlowCancelled());
    }

    _view._show(title, help, build(done, cancel));
    return completer.future;
  }

  /// Browse folders under the project and pick one.
  Future<String> pickFolder(String title,
          {String? help, String action = 'Create here', String? start}) =>
      _step(title, help, (done, cancel) {
        final project = app.project;
        return FolderPicker(
          rootPath: root,
          startPath: start,
          actionLabel: action,
          excluded: [if (project != null) project.outputPath],
          onSelected: done,
          onCancel: cancel,
        );
      });

  Future<String> text(
    String title, {
    String? help,
    String initial = '',
    String? placeholder,
    String? Function(String value)? validate,
    bool allowEmpty = false,
    List<String> suggestions = const [],
  }) =>
      _step(
          title,
          help,
          (done, cancel) => TextPrompt(
                initial: initial,
                placeholder: placeholder,
                validate: validate,
                allowEmpty: allowEmpty,
                suggestions: suggestions,
                onSubmit: done,
                onCancel: cancel,
              ));

  Future<T> select<T>(String title, List<SelectItem<T>> items,
          {String? help,
          bool filterable = false,
          String emptyText = 'Nothing here.'}) =>
      _step(
          title,
          help,
          (done, cancel) => SelectList<T>(
                items: items,
                filterable: filterable || items.length > 12,
                emptyText: emptyText,
                onSelect: done,
                onCancel: cancel,
              ));

  Future<Set<T>> multiSelect<T>(String title, List<SelectItem<T>> items,
          {String? help, Set<T> selected = const {}}) =>
      _step(
          title,
          help,
          (done, cancel) => SelectList<T>(
                items: items,
                multi: true,
                initiallySelected: selected,
                onConfirm: done,
                onCancel: cancel,
              ));

  /// Ask yes or no. Esc means no.
  Future<bool> confirm(String title,
          {List<Line> details = const [],
          String yes = 'Yes',
          bool danger = false}) =>
      _step<bool>(
          title,
          null,
          (done, cancel) => MessageView(
                lines: [
                  ...details,
                  if (details.isNotEmpty) const Line(''),
                  Line(
                      danger
                          ? '$yes? This cannot be undone. (y/n)'
                          : '$yes? (y/n)',
                      danger ? Tone.error : Tone.accent),
                ],
                hints: 'y ${yes.toLowerCase()}  n / Esc cancel  ↑↓ scroll',
                onKey: (event) {
                  final ch = event.character?.toLowerCase();
                  if (ch == 'y' ||
                      (!danger && event.logicalKey == LogicalKey.enter)) {
                    done(true);
                  } else if (ch == 'n' ||
                      event.logicalKey == LogicalKey.escape) {
                    done(false);
                  } else {
                    return false;
                  }
                  return true;
                },
              ));

  /// Show lines until Enter or Esc.
  Future<void> show(String title, List<Line> lines) => _step<void>(
      title,
      null,
      (done, cancel) => MessageView(
            lines: lines,
            hints: 'Enter / Esc close  ↑↓ scroll',
            onKey: (event) {
              if (event.logicalKey == LogicalKey.enter ||
                  event.logicalKey == LogicalKey.escape) {
                done(null);
                return true;
              }
              return false;
            },
          ));

  /// Run [op], log what it did, regenerate when files changed (and
  /// [regenerate] is set), and show a summary.
  Future<OpResult> run(String title, OpResult Function() op,
      {bool regenerate = true, String? summary}) async {
    final result = op();
    final lines = <Line>[
      for (final f in result.created)
        Line('  created  ${rel(f)}', Tone.success),
      for (final f in result.changed) Line('  updated  ${rel(f)}', Tone.accent),
      for (final f in result.deleted)
        Line('  deleted  ${rel(f)}', Tone.warning),
      for (final s in result.skipped) Line('  skipped  $s', Tone.muted),
    ];
    if (!result.touchedFiles) {
      lines.add(const Line('Nothing changed.', Tone.muted));
    }
    for (final l in lines) {
      app.log(l.text.trim(), l.tone);
    }
    if (summary != null) {
      lines.insert(0, Line(summary, Tone.success));
      lines.insert(1, const Line(''));
      app.log(summary, Tone.success);
    }
    if (regenerate && result.touchedFiles) {
      final generation = app.generate();
      result.generation = generation;
      lines
        ..add(const Line(''))
        ..add(generation.success
            ? Line(
                'Regenerated ${generation.keyCount} key(s) in '
                '${generation.moduleCount} module(s).',
                Tone.success)
            : const Line('Generation failed — see the log below.', Tone.error));
    } else {
      app.reload();
    }
    await show(title, lines);
    return result;
  }
}

/// Shows the current step of a running action.
class FlowView extends StatefulComponent {
  const FlowView(
      {super.key,
      required this.action,
      required this.app,
      required this.onDone});

  final GuiAction action;
  final GuiController app;
  final VoidCallback onDone;

  @override
  State<FlowView> createState() => _FlowViewState();
}

class _FlowViewState extends State<FlowView> {
  String? _title;
  String? _help;
  Component? _body;
  int _stepCount = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_start);
  }

  void _show(String title, String? help, Component body) {
    if (!mounted || _finished) return;
    setState(() {
      _title = title;
      _help = help;
      _stepCount++;
      _body = _Step(key: ValueKey(_stepCount), child: body);
    });
  }

  Future<void> _start() async {
    final f = FlowContext._(this);
    try {
      await component.action.run(f);
    } on FlowCancelled {
      // Esc: back to the menu.
    } on OpException catch (e) {
      component.app.log(e.message, Tone.error);
      try {
        await f.show('Could not ${component.action.label.toLowerCase()}',
            [Line(e.message, Tone.error)]);
      } on FlowCancelled {
        // Closed.
      }
    } on Object catch (e, stack) {
      component.app.log('Unexpected error: $e', Tone.error);
      component.app.log('$stack', Tone.muted);
      try {
        await f.show('Something went wrong', [Line('$e', Tone.error)]);
      } on FlowCancelled {
        // Closed.
      }
    }
    _finished = true;
    if (mounted) component.onDone();
  }

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final title = _title == null
        ? component.action.label
        : '${component.action.label}  ›  $_title';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title,
            style:
                TextStyle(color: theme.primary, fontWeight: FontWeight.bold)),
        if (_help != null) Text(_help!, style: TextStyle(color: theme.outline)),
        const SizedBox(height: 1),
        Expanded(child: _body ?? const Text('…')),
      ],
    );
  }
}

/// Gives each step its own key, so two steps of the same type (two text
/// prompts in a row) never share state.
class _Step extends StatelessComponent {
  const _Step({super.key, required this.child});
  final Component child;

  @override
  Component build(BuildContext context) => child;
}
