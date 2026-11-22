import 'dart:io';

import 'package:nocterm/nocterm.dart';
import 'package:path/path.dart' as p;

/// Folders never offered: tool output, VCS data and platform build trees.
const _hiddenFolders = {
  'build',
  '.dart_tool',
  '.git',
  '.idea',
  '.vscode',
  'node_modules',
};

enum _EntryKind { createHere, newFolder, up, folder }

class _Entry {
  const _Entry(this.kind, this.label, [this.path]);
  final _EntryKind kind;
  final String label;
  final String? path;
}

/// Browse the project's folders and pick one.
///
/// Enter opens a folder (or runs the action row), Backspace or ← goes up,
/// `n` creates a folder, Esc cancels. The picker never leaves [rootPath].
class FolderPicker extends StatefulComponent {
  const FolderPicker({
    super.key,
    required this.rootPath,
    required this.onSelected,
    this.onCancel,
    this.startPath,
    this.actionLabel = 'Create here',
    this.excluded = const [],
    this.focused = true,
  });

  /// The project root; navigation stops here.
  final String rootPath;

  /// Where browsing starts; defaults to `lib/` when it exists.
  final String? startPath;
  final String actionLabel;

  /// Absolute paths to leave out (for example the generated output folder).
  final List<String> excluded;
  final bool focused;
  final void Function(String path) onSelected;
  final VoidCallback? onCancel;

  @override
  State<FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<FolderPicker> {
  late String _current;
  List<_Entry> _entries = const [];
  int _index = 0;
  bool _creating = false;
  String? _error;
  final _scroll = ScrollController();
  final _newName = TextEditingController();

  @override
  void initState() {
    super.initState();
    final lib = p.join(component.rootPath, 'lib');
    _current = component.startPath ??
        (Directory(lib).existsSync() ? lib : component.rootPath);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _newName.dispose();
    super.dispose();
  }

  bool get _atRoot => p.equals(_current, component.rootPath);

  void _load([String? select]) {
    final excluded = component.excluded.map(p.normalize).toSet();
    final folders = <String>[];
    try {
      for (final entity in Directory(_current).listSync()) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('.') || _hiddenFolders.contains(name)) continue;
        if (excluded.contains(p.normalize(entity.path))) continue;
        folders.add(entity.path);
      }
    } on FileSystemException catch (e) {
      _error = e.message;
    }
    folders.sort((a, b) =>
        p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()));

    _entries = [
      _Entry(_EntryKind.createHere, '▶ ${component.actionLabel}'),
      const _Entry(_EntryKind.newFolder, '+ New folder'),
      if (!_atRoot) const _Entry(_EntryKind.up, '..'),
      for (final f in folders) _Entry(_EntryKind.folder, p.basename(f), f),
    ];
    final selected =
        select == null ? -1 : _entries.indexWhere((e) => e.path == select);
    _index = selected >= 0 ? selected : 0;
    _scroll.ensureIndexVisible(index: _index);
  }

  void _move(int delta) {
    setState(() {
      _index = (_index + delta).clamp(0, _entries.length - 1);
      _scroll.ensureIndexVisible(index: _index);
    });
  }

  void _goUp() {
    if (_atRoot) return;
    setState(() {
      final previous = _current;
      _current = p.dirname(_current);
      _error = null;
      _load(previous);
    });
  }

  void _activate() {
    final entry = _entries[_index];
    switch (entry.kind) {
      case _EntryKind.createHere:
        component.onSelected(_current);
      case _EntryKind.newFolder:
        setState(() {
          _creating = true;
          _error = null;
          _newName.text = '';
        });
      case _EntryKind.up:
        _goUp();
      case _EntryKind.folder:
        setState(() {
          _current = entry.path!;
          _error = null;
          _load();
        });
    }
  }

  void _createFolder(String raw) {
    final name = raw.trim();
    if (name.isEmpty) {
      setState(() => _creating = false);
      return;
    }
    if (name.contains('/') || name.contains(r'\') || name.startsWith('.')) {
      setState(() => _error = 'Enter a single folder name.');
      return;
    }
    final path = p.join(_current, name);
    try {
      Directory(path).createSync();
    } on FileSystemException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _creating = false;
      _error = null;
      _current = path;
      _load();
    });
  }

  bool _onKey(KeyboardEvent event) {
    if (_creating) {
      if (event.logicalKey == LogicalKey.escape) {
        setState(() => _creating = false);
        return true;
      }
      return false;
    }
    final key = event.logicalKey;
    if (key == LogicalKey.arrowDown || event.character == 'j') {
      _move(1);
    } else if (key == LogicalKey.arrowUp || event.character == 'k') {
      _move(-1);
    } else if (key == LogicalKey.pageDown) {
      _move(10);
    } else if (key == LogicalKey.pageUp) {
      _move(-10);
    } else if (key == LogicalKey.enter || key == LogicalKey.arrowRight) {
      if (key == LogicalKey.arrowRight &&
          _entries[_index].kind != _EntryKind.folder) {
        return false;
      }
      _activate();
    } else if (key == LogicalKey.backspace || key == LogicalKey.arrowLeft) {
      _goUp();
    } else if (event.character == 'n') {
      _index = 1;
      _activate();
    } else if (key == LogicalKey.escape) {
      component.onCancel?.call();
    } else {
      return false;
    }
    return true;
  }

  bool _hasL10n(String path) => Directory(p.join(path, 'l10n')).existsSync();

  @override
  Component build(BuildContext context) {
    final relative = p.relative(_current, from: component.rootPath);
    final shown = relative == '.' ? './' : '${p.split(relative).join('/')}/';

    return Focusable(
      focused: component.focused && !_creating,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(shown, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemCount: _entries.length,
              itemBuilder: (context, i) {
                final entry = _entries[i];
                final selected = i == _index;
                final isAction = entry.kind == _EntryKind.createHere ||
                    entry.kind == _EntryKind.newFolder;
                final badge =
                    entry.kind == _EntryKind.folder && _hasL10n(entry.path!)
                        ? '  [l10n]'
                        : '';
                final label = entry.kind == _EntryKind.folder
                    ? '${entry.label}/$badge'
                    : entry.label;
                return GestureDetector(
                  onTap: () {
                    setState(() => _index = i);
                    _activate();
                  },
                  child: Container(
                    decoration: selected
                        ? const BoxDecoration(color: Colors.cyan)
                        : null,
                    child: Text(
                      ' $label',
                      style: TextStyle(
                        color: selected
                            ? Colors.black
                            : isAction
                                ? Colors.cyan
                                : null,
                        fontWeight:
                            isAction ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_creating)
            Row(children: [
              const Text('New folder: '),
              Expanded(
                child: TextField(
                  controller: _newName,
                  focused: true,
                  placeholder: 'folder_name',
                  onSubmitted: _createFolder,
                ),
              ),
            ]),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          const Text(
            '↑↓ move  Enter open/select  ← up  n new folder  Esc cancel',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
