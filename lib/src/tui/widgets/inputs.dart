/// The building blocks every GUI screen is made of: a list to pick from, a
/// text prompt, and a scrollable message view.
library;

import 'package:nocterm/nocterm.dart';

/// Hint line at the bottom of a step.
class KeyHints extends StatelessComponent {
  const KeyHints(this.text, {super.key});
  final String text;

  @override
  Component build(BuildContext context) => Text(
        text,
        style: TextStyle(color: TuiTheme.of(context).outline),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      );
}

/// A row in a [SelectList].
class SelectItem<T> {
  const SelectItem(this.value, this.label, {this.detail, this.enabled = true});

  final T value;
  final String label;

  /// Dimmed text after the label.
  final String? detail;
  final bool enabled;
}

/// A keyboard- and mouse-driven list.
///
/// Single mode: Enter picks the highlighted item. Multi mode ([multi]):
/// Space toggles, `a` toggles all, Enter confirms. With [filterable], typing
/// narrows the list.
class SelectList<T> extends StatefulComponent {
  const SelectList({
    super.key,
    required this.items,
    this.onSelect,
    this.onConfirm,
    this.onCancel,
    this.onHighlight,
    this.multi = false,
    this.initiallySelected = const {},
    this.filterable = false,
    this.focused = true,
    this.emptyText = 'Nothing here.',
    this.initialIndex = 0,
    this.showHints = true,
  });

  final List<SelectItem<T>> items;
  final void Function(T value)? onSelect;
  final void Function(Set<T> values)? onConfirm;
  final VoidCallback? onCancel;
  final void Function(T value)? onHighlight;
  final bool multi;
  final Set<T> initiallySelected;
  final bool filterable;
  final bool focused;
  final String emptyText;
  final int initialIndex;
  final bool showHints;

  @override
  State<SelectList<T>> createState() => _SelectListState<T>();
}

class _SelectListState<T> extends State<SelectList<T>> {
  late int _index = component.initialIndex;
  late final Set<T> _selected = {...component.initiallySelected};
  String _filter = '';
  final _scroll = ScrollController();

  List<SelectItem<T>> get _visible {
    if (_filter.isEmpty) return component.items;
    final f = _filter.toLowerCase();
    return component.items
        .where((i) =>
            i.label.toLowerCase().contains(f) ||
            (i.detail?.toLowerCase().contains(f) ?? false))
        .toList();
  }

  @override
  void didUpdateComponent(SelectList<T> old) {
    super.didUpdateComponent(old);
    _clamp();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _clamp() {
    final n = _visible.length;
    _index = n == 0 ? 0 : _index.clamp(0, n - 1);
  }

  void _move(int delta) {
    final items = _visible;
    if (items.isEmpty) return;
    setState(() {
      _index = (_index + delta).clamp(0, items.length - 1);
      _scroll.ensureIndexVisible(index: _index);
    });
    component.onHighlight?.call(items[_index].value);
  }

  void _activate(int i) {
    final items = _visible;
    if (i < 0 || i >= items.length || !items[i].enabled) return;
    if (component.multi) {
      setState(() {
        final v = items[i].value;
        _selected.contains(v) ? _selected.remove(v) : _selected.add(v);
      });
    } else {
      component.onSelect?.call(items[i].value);
    }
  }

  bool _onKey(KeyboardEvent event) {
    final key = event.logicalKey;
    final ch = event.character;
    if (key == LogicalKey.arrowDown || (!component.filterable && ch == 'j')) {
      _move(1);
    } else if (key == LogicalKey.arrowUp ||
        (!component.filterable && ch == 'k')) {
      _move(-1);
    } else if (key == LogicalKey.pageDown) {
      _move(10);
    } else if (key == LogicalKey.pageUp) {
      _move(-10);
    } else if (key == LogicalKey.home) {
      _move(-_index);
    } else if (key == LogicalKey.end) {
      _move(_visible.length);
    } else if (key == LogicalKey.enter) {
      if (component.multi) {
        component.onConfirm?.call({..._selected});
      } else {
        _activate(_index);
      }
    } else if (component.multi && key == LogicalKey.space) {
      _activate(_index);
    } else if (component.multi && ch == 'a' && !component.filterable) {
      setState(() {
        final all =
            component.items.where((i) => i.enabled).map((i) => i.value).toSet();
        if (_selected.containsAll(all)) {
          _selected.clear();
        } else {
          _selected.addAll(all);
        }
      });
    } else if (key == LogicalKey.escape) {
      if (_filter.isNotEmpty) {
        setState(() {
          _filter = '';
          _clamp();
        });
      } else {
        component.onCancel?.call();
      }
    } else if (component.filterable && key == LogicalKey.backspace) {
      if (_filter.isEmpty) return false;
      setState(() {
        _filter = _filter.substring(0, _filter.length - 1);
        _clamp();
      });
    } else if (component.filterable &&
        ch != null &&
        ch.length == 1 &&
        ch.codeUnitAt(0) >= 32 &&
        !event.isControlPressed &&
        !(component.multi && ch == ' ')) {
      setState(() {
        _filter += ch;
        _index = 0;
      });
    } else {
      return false;
    }
    return true;
  }

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final items = _visible;
    final hints = component.multi
        ? '↑↓ move  Space toggle${component.filterable ? '' : '  a all'}  Enter confirm  Esc back'
        : '↑↓ move  Enter select  Esc back';

    return Focusable(
      focused: component.focused,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (component.filterable)
            Text(
              _filter.isEmpty ? 'Type to filter…' : 'Filter: $_filter▏',
              style: TextStyle(
                  color: _filter.isEmpty ? theme.outline : theme.primary),
            ),
          Expanded(
            child: items.isEmpty
                ? Text(component.emptyText,
                    style: TextStyle(color: theme.outline))
                : ListView.builder(
                    controller: _scroll,
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final highlighted = i == _index && component.focused;
                      final box = component.multi
                          ? (_selected.contains(item.value) ? '[x] ' : '[ ] ')
                          : (i == _index ? '› ' : '  ');
                      final fg = highlighted
                          ? theme.onPrimary
                          : item.enabled
                              ? null
                              : theme.outline;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _index = i);
                          _activate(i);
                        },
                        child: Container(
                          decoration: highlighted
                              ? BoxDecoration(color: theme.primary)
                              : null,
                          child: Row(children: [
                            Text('$box${item.label}',
                                style: TextStyle(color: fg)),
                            if (item.detail != null)
                              Expanded(
                                child: Text(
                                  '  ${item.detail}',
                                  style: TextStyle(
                                      color: highlighted ? fg : theme.outline),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
          if (component.showHints) KeyHints(hints),
        ],
      ),
    );
  }
}

/// A one-line text input with validation.
class TextPrompt extends StatefulComponent {
  const TextPrompt({
    super.key,
    required this.onSubmit,
    this.onCancel,
    this.initial = '',
    this.placeholder,
    this.validate,
    this.allowEmpty = false,
    this.focused = true,
    this.suggestions = const [],
  });

  final void Function(String value) onSubmit;
  final VoidCallback? onCancel;
  final String initial;
  final String? placeholder;
  final String? Function(String value)? validate;
  final bool allowEmpty;
  final bool focused;

  /// Shown under the field; Tab cycles through them.
  final List<String> suggestions;

  @override
  State<TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<TextPrompt> {
  late final _controller = TextEditingController(text: component.initial);
  String? _error;
  int _suggestion = -1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    final value = raw.trim();
    if (value.isEmpty && !component.allowEmpty) {
      setState(() => _error = 'A value is required.');
      return;
    }
    final error = value.isEmpty ? null : component.validate?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    component.onSubmit(value);
  }

  bool _onKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.escape) {
      component.onCancel?.call();
      return true;
    }
    if (event.logicalKey == LogicalKey.tab &&
        component.suggestions.isNotEmpty) {
      setState(() {
        _suggestion = (_suggestion + 1) % component.suggestions.length;
        _controller.text = component.suggestions[_suggestion];
        _error = null;
      });
      return true;
    }
    return false;
  }

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Focusable(
      focused: component.focused,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration:
                BoxDecoration(border: BoxBorder.all(color: theme.primary)),
            child: TextField(
              controller: _controller,
              focused: component.focused,
              placeholder: component.placeholder,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: _submit,
            ),
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: theme.error)),
          if (component.suggestions.isNotEmpty)
            Text(
              'Suggestions (Tab): ${component.suggestions.take(8).join(', ')}',
              style: TextStyle(color: theme.outline),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          const Spacer(),
          const KeyHints('Enter confirm  Esc back'),
        ],
      ),
    );
  }
}

/// Coloured lines for a [MessageView].
enum Tone { normal, muted, accent, success, warning, error }

class Line {
  const Line(this.text, [this.tone = Tone.normal]);
  final String text;
  final Tone tone;
}

Color? toneColor(TuiThemeData theme, Tone tone) => switch (tone) {
      Tone.normal => null,
      Tone.muted => theme.outline,
      Tone.accent => theme.primary,
      Tone.success => theme.success,
      Tone.warning => theme.warning,
      Tone.error => theme.error,
    };

/// Scrollable lines with a set of key actions (Enter, y/n…).
class MessageView extends StatefulComponent {
  const MessageView({
    super.key,
    required this.lines,
    required this.onKey,
    this.hints = 'Enter continue',
    this.focused = true,
  });

  final List<Line> lines;

  /// Return true when the key was handled. Arrow keys scroll.
  final bool Function(KeyboardEvent event) onKey;
  final String hints;
  final bool focused;

  @override
  State<MessageView> createState() => _MessageViewState();
}

class _MessageViewState extends State<MessageView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Focusable(
      focused: component.focused,
      onKeyEvent: (event) {
        if (component.onKey(event)) return true;
        final key = event.logicalKey;
        if (key == LogicalKey.arrowDown) {
          _scroll.scrollDown(1);
        } else if (key == LogicalKey.arrowUp) {
          _scroll.scrollUp(1);
        } else if (key == LogicalKey.pageDown) {
          _scroll.scrollDown(10);
        } else if (key == LogicalKey.pageUp) {
          _scroll.scrollUp(10);
        } else {
          return false;
        }
        setState(() {});
        return true;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemCount: component.lines.length,
              itemBuilder: (context, i) {
                final line = component.lines[i];
                return Text(line.text,
                    style: TextStyle(color: toneColor(theme, line.tone)));
              },
            ),
          ),
          KeyHints(component.hints),
        ],
      ),
    );
  }
}
