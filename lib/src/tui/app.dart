/// The terminal GUI: `modular_l10n_generator gui`.
library;

import 'package:nocterm/nocterm.dart' hide Logger;
import 'package:path/path.dart' as p;

import '../ops/doctor_ops.dart';
import '../version.dart';
import 'actions.dart';
import 'controller.dart';
import 'flow.dart';
import 'widgets/inputs.dart';

/// Run the GUI for the project at [rootPath] until the user quits.
Future<void> runGui(String rootPath) async {
  final controller = GuiController(rootPath);
  try {
    await runApp(
      NoctermApp(title: 'Modular L10n', child: L10nApp(controller: controller)),
      enableHotReload: false,
    );
  } finally {
    controller.dispose();
  }
}

class L10nApp extends StatefulComponent {
  const L10nApp({super.key, required this.controller, this.actions});

  final GuiController controller;

  /// Defaults to [guiActions]; replaced in tests.
  final List<GuiAction>? actions;

  @override
  State<L10nApp> createState() => _L10nAppState();
}

class _L10nAppState extends State<L10nApp> {
  late final List<GuiAction> _actions = component.actions ?? guiActions;
  int _index = 0;
  GuiAction? _running;
  bool _bigLog = false;
  bool _help = false;
  List<DoctorItem> _problems = const [];
  final _sidebarScroll = ScrollController();

  GuiController get _app => component.controller;

  @override
  void initState() {
    super.initState();
    _app.addListener(_changed);
    _refreshProblems();
  }

  @override
  void dispose() {
    _app.removeListener(_changed);
    _sidebarScroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _refreshProblems() {
    _problems = diagnoseProject(_app.rootPath)
        .where((i) => i.status != DoctorStatus.ok)
        .toList();
  }

  void _start(GuiAction action) {
    setState(() {
      _help = false;
      _running = action;
    });
  }

  void _finished() {
    setState(() {
      _running = null;
      _refreshProblems();
    });
  }

  void _move(int delta) {
    setState(() {
      _index = (_index + delta).clamp(0, _actions.length - 1);
      _sidebarScroll.ensureIndexVisible(index: _rowOf(_index));
    });
  }

  /// Sidebar row of action [i], counting group headers.
  int _rowOf(int i) {
    var row = 0;
    String? group;
    for (var a = 0; a <= i; a++) {
      if (_actions[a].group != group) {
        group = _actions[a].group;
        row += a == 0 ? 1 : 2;
      }
      if (a < i) row++;
    }
    return row;
  }

  bool _onKey(KeyboardEvent event) {
    final key = event.logicalKey;
    final ch = event.character;
    if (key == LogicalKey.keyC && event.isControlPressed) return false;
    if (_running != null) return false;

    if (_help) {
      setState(() => _help = false);
      return true;
    }
    if (key == LogicalKey.arrowDown || ch == 'j') {
      _move(1);
    } else if (key == LogicalKey.arrowUp || ch == 'k') {
      _move(-1);
    } else if (key == LogicalKey.enter || key == LogicalKey.arrowRight) {
      _start(_actions[_index]);
    } else if (ch == 'q' || key == LogicalKey.escape) {
      shutdownApp();
    } else if (ch == 'w') {
      _app.toggleWatch();
    } else if (ch == 'v') {
      setState(() => _bigLog = !_bigLog);
    } else if (ch == 'r') {
      _app.reload();
      setState(_refreshProblems);
      _app.log('Reloaded the project.', Tone.muted);
    } else if (ch == '?') {
      setState(() => _help = true);
    } else if (ch != null) {
      final match = _actions.indexWhere((a) => a.shortcut == ch);
      if (match < 0) return false;
      setState(() => _index = match);
      _start(_actions[match]);
    } else {
      return false;
    }
    return true;
  }

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Focusable(
      focused: true,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(theme),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sidebar(theme),
                Expanded(child: _main(theme)),
              ],
            ),
          ),
          _logPanel(theme),
          KeyHints(_running == null
              ? '↑↓ move  Enter open  letters: shortcuts  w watch  v log  r reload  ? help  q quit'
              : 'Esc back  Ctrl+C quit'),
        ],
      ),
    );
  }

  Component _header(TuiThemeData theme) {
    final project = _app.project;
    final name = p.basename(_app.rootPath);
    final info = project == null
        ? 'not loaded'
        : '${project.config.className} · ${project.locales.isEmpty ? 'no locales' : project.locales.join(' ')}'
            ' · ${project.modules.length} module(s)';
    return Container(
      decoration: BoxDecoration(color: theme.primary),
      child: Row(children: [
        Text(' Modular L10n ',
            style:
                TextStyle(color: theme.onPrimary, fontWeight: FontWeight.bold)),
        Text('· $name ', style: TextStyle(color: theme.onPrimary)),
        const Spacer(),
        Text('$info  ', style: TextStyle(color: theme.onPrimary)),
        Text(_app.watching ? '● watching ' : '○ watch off ',
            style: TextStyle(
                color: theme.onPrimary,
                fontWeight: _app.watching ? FontWeight.bold : null)),
      ]),
    );
  }

  Component _sidebar(TuiThemeData theme) {
    final rows = <Component>[];
    String? group;
    for (var i = 0; i < _actions.length; i++) {
      final a = _actions[i];
      if (a.group != group) {
        // Not const: nocterm's ListView asserts when a child is the same
        // instance on rebuild.
        if (group != null) rows.add(Text(''));
        group = a.group;
        rows.add(Text(' ${group.toUpperCase()}',
            style:
                TextStyle(color: theme.outline, fontWeight: FontWeight.bold)));
      }
      final selected = i == _index;
      final active = _running == null;
      rows.add(GestureDetector(
        onTap: () {
          if (_running != null) return;
          setState(() => _index = i);
          _start(a);
        },
        child: Container(
          decoration:
              selected && active ? BoxDecoration(color: theme.primary) : null,
          child: Row(children: [
            Text(
              ' ${selected ? '›' : ' '} ${a.label}',
              style: TextStyle(
                color: selected && active
                    ? theme.onPrimary
                    : active
                        ? null
                        : theme.outline,
                fontWeight: selected ? FontWeight.bold : null,
              ),
            ),
            const Spacer(),
            if (a.shortcut != null)
              Text('${a.shortcut} ',
                  style: TextStyle(
                      color: selected && active
                          ? theme.onPrimary
                          : theme.outline)),
          ]),
        ),
      ));
    }
    return Container(
      width: 30,
      decoration: BoxDecoration(
        border: BoxBorder.all(
            color: _running == null ? theme.primary : theme.outline),
        title: const BorderTitle(text: ' Actions '),
      ),
      child: ListView(controller: _sidebarScroll, children: rows),
    );
  }

  Component _main(TuiThemeData theme) {
    final running = _running;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        border: BoxBorder.all(
            color: running != null ? theme.primary : theme.outline),
        title: BorderTitle(
            text: running != null ? ' ${running.label} ' : ' Overview '),
      ),
      child: running != null
          ? FlowView(
              key: ValueKey(running),
              action: running,
              app: _app,
              onDone: _finished)
          : _help
              ? _helpView(theme)
              : _overview(theme),
    );
  }

  Component _overview(TuiThemeData theme) {
    final project = _app.project;
    final a = _actions[_index];
    final lines = <Line>[
      Line(a.label, Tone.accent),
      Line(a.description),
      const Line('Press Enter to start.', Tone.muted),
      const Line(''),
      if (_app.loadError != null)
        Line('Cannot load the project: ${_app.loadError}', Tone.error),
      if (_problems.isNotEmpty) ...[
        Line('${_problems.length} setup problem(s) — press d for Doctor:',
            Tone.warning),
        for (final pr in _problems.take(4))
          Line('  ${pr.status == DoctorStatus.error ? '✗' : '!'} ${pr.title}',
              pr.status == DoctorStatus.error ? Tone.error : Tone.warning),
        const Line(''),
      ],
      if (project != null && project.modules.isEmpty)
        const Line('No modules yet. Start with Initialize, or Create module.',
            Tone.accent),
      if (project != null && project.modules.isNotEmpty) ...[
        Line('Modules (default locale: ${project.defaultLocale})', Tone.muted),
        for (final m in ([
          ...project.modules
        ]..sort((x, y) => x.name.compareTo(y.name))))
          Line(
              '  ${m.name.padRight(20)} ${m.arbFiles.map((f) => f.locale).join(' ').padRight(18)} '
              '${p.relative(project.l10nDir(m), from: _app.rootPath)}'),
      ],
    ];
    return ListView(children: [
      for (final l in lines)
        Text(l.text, style: TextStyle(color: toneColor(theme, l.tone))),
    ]);
  }

  Component _helpView(TuiThemeData theme) {
    const lines = [
      Line('Keys', Tone.accent),
      Line('  ↑ ↓  j k       move in lists'),
      Line('  Enter          open an action / confirm'),
      Line('  Esc            go back (cancels the current action)'),
      Line('  letters        shortcuts shown next to the actions'),
      Line('  w              watch mode: regenerate when ARB files change'),
      Line('  v              larger log panel'),
      Line('  r              reload the project from disk'),
      Line('  q / Ctrl+C     quit'),
      Line(''),
      Line('In the folder picker', Tone.accent),
      Line('  Enter opens a folder, ← goes up, n makes a new folder,'),
      Line('  and the ▶ row at the top selects the folder you are in.'),
      Line(''),
      Line('Every action is also a command for scripts and CI:', Tone.accent),
      Line('  dart run modular_l10n_generator --help'),
      Line(''),
      Line('modular_l10n_generator $packageVersion', Tone.muted),
    ];
    return ListView(children: [
      for (final l in lines)
        Text(l.text, style: TextStyle(color: toneColor(theme, l.tone))),
    ]);
  }

  Component _logPanel(TuiThemeData theme) {
    final logs = _app.logs;
    return Container(
      height: _bigLog ? 14 : 6,
      decoration: BoxDecoration(
        border: BoxBorder.all(color: theme.outline),
        title: const BorderTitle(text: ' Log '),
      ),
      child: logs.isEmpty
          ? Text(' Output from actions appears here.',
              style: TextStyle(color: theme.outline))
          : ListView.builder(
              // Reversed, so the newest line is always visible at the bottom.
              reverse: true,
              itemCount: logs.length,
              itemBuilder: (context, i) => Text(
                  ' ${logs[logs.length - 1 - i].text}',
                  style: TextStyle(
                      color: toneColor(theme, logs[logs.length - 1 - i].tone)),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            ),
    );
  }
}
