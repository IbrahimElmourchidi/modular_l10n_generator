/// Every action the GUI offers, each written as a flow of steps.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../config.dart';
import '../dart_generator.dart' show toCamelCase;
import '../generate.dart' show loadConfig;
import '../ops/arb_file.dart';
import '../ops/check_ops.dart';
import '../ops/doctor_ops.dart';
import '../ops/exchange_ops.dart';
import '../ops/key_ops.dart';
import '../ops/locale_ops.dart';
import '../ops/maintenance_ops.dart';
import '../ops/module_ops.dart';
import '../ops/project.dart';
import '../ops/pubspec_writer.dart';
import '../ops/scan_ops.dart';
import 'flow.dart';
import 'widgets/inputs.dart';

/// Locales offered as suggestions when adding one.
const commonLocales = [
  'en', 'ar', 'fr', 'de', 'es', 'it', 'pt', 'pt_BR', 'ru', 'zh_Hans', //
  'zh_Hant', 'ja', 'ko', 'hi', 'tr', 'nl', 'sv', 'pl', 'id', 'fa', 'he',
  'ur', 'uk', 'vi', 'th', 'bn', 'ms', 'el', 'cs', 'ro', 'hu', 'da', 'fi',
];

final List<GuiAction> guiActions = [
  // ── Project ──
  GuiAction(
    group: 'Project',
    label: 'Generate',
    shortcut: 'g',
    description: 'Generate the Dart code from the ARB files now.',
    run: (f) async {
      final r = f.app.generate();
      await f.show('Result', [
        r.success
            ? Line(
                r.skipped
                    ? 'Generation is disabled (modular_l10n.enabled: false).'
                    : 'Generated ${r.keyCount} key(s) · ${r.moduleCount} module(s) · '
                        '${r.locales.length} locale(s)',
                Tone.success)
            : const Line('Generation failed.', Tone.error),
        if (r.writtenFiles.isEmpty && r.success && !r.skipped)
          const Line('Everything was already up to date.', Tone.muted),
        for (final file in r.writtenFiles)
          Line('  wrote ${f.rel(file)}', Tone.muted),
        if (r.warningCount > 0)
          Line('${r.warningCount} warning(s) — see the log below.',
              Tone.warning),
      ]);
    },
  ),
  GuiAction(
    group: 'Project',
    label: 'Doctor',
    shortcut: 'd',
    description:
        'Check the setup: config, modules, dependencies, Flutter Intl conflicts.',
    run: _doctor,
  ),
  GuiAction(
    group: 'Project',
    label: 'Initialize',
    description:
        'Add the modular_l10n section to pubspec.yaml and create the first module.',
    run: _init,
  ),
  GuiAction(
    group: 'Project',
    label: 'Settings',
    description: 'Edit the modular_l10n settings in pubspec.yaml.',
    run: _settings,
  ),

  // ── Modules & keys ──
  GuiAction(
    group: 'Modules & keys',
    label: 'Create module',
    shortcut: 'm',
    description: 'Pick a folder and create its l10n/ ARB files.',
    run: _createModule,
  ),
  GuiAction(
    group: 'Modules & keys',
    label: 'Add key',
    shortcut: 'a',
    description: 'Add a translation key to a module, in every locale.',
    run: _addKey,
  ),
  GuiAction(
    group: 'Modules & keys',
    label: 'Translate',
    shortcut: 't',
    description: 'Fill in missing and empty translations, one key at a time.',
    run: _translate,
  ),
  GuiAction(
    group: 'Modules & keys',
    label: 'Rename key',
    description: 'Rename a key in every locale and in your Dart code.',
    run: _renameKey,
  ),

  // ── Locales ──
  GuiAction(
    group: 'Locales',
    label: 'Add locale',
    shortcut: 'l',
    description: 'Add a language to every module.',
    run: _addLocale,
  ),
  GuiAction(
    group: 'Locales',
    label: 'Remove locale',
    description: "Delete a language's ARB files from every module.",
    run: _removeLocale,
  ),
  GuiAction(
    group: 'Locales',
    label: 'Pseudo-locale',
    description:
        'Accented, longer text to test layouts and spot hardcoded strings.',
    run: _pseudo,
  ),

  // ── Quality ──
  GuiAction(
    group: 'Quality',
    label: 'Check',
    shortcut: 'c',
    description: 'Missing translations, ICU mistakes, direct module imports.',
    run: _check,
  ),
  GuiAction(
    group: 'Quality',
    label: 'Hardcoded strings',
    shortcut: 'h',
    description: 'Find UI text in Dart code and move it into ARB files.',
    run: _hardcoded,
  ),
  GuiAction(
    group: 'Quality',
    label: 'Unused keys',
    description: 'Keys no Dart file references; remove the ones you pick.',
    run: _unused,
  ),
  GuiAction(
    group: 'Quality',
    label: 'Sort keys',
    description: 'Sort ARB keys alphabetically.',
    run: (f) async {
      final project = f.project;
      final module = await _pickModule(f, 'Which module?', allowAll: true);
      await f.run('Sorted', () => sortArbFiles(project, module: module));
    },
  ),

  // ── Exchange ──
  GuiAction(
    group: 'Exchange',
    label: 'Export',
    description:
        'Write translations to CSV (spreadsheets) or XLIFF (translation tools).',
    run: _export,
  ),
  GuiAction(
    group: 'Exchange',
    label: 'Import',
    description: 'Read a CSV or XLIFF file back into the ARB files.',
    run: _import,
  ),
  GuiAction(
    group: 'Exchange',
    label: 'Migrate from Flutter Intl',
    description: 'Move intl_*.arb files into modules.',
    run: _migrate,
  ),
];

// ─── Shared steps ───────────────────────────────────────────────────────────

/// Pick a module; `null` means "all" when [allowAll].
Future<String?> _pickModule(FlowContext f, String title,
    {bool allowAll = false}) async {
  final project = f.project;
  if (project.modules.isEmpty) {
    throw OpException('There are no modules yet. Use "Create module" first.');
  }
  final modules = [...project.modules]
    ..sort((a, b) => a.name.compareTo(b.name));
  if (modules.length == 1 && !allowAll) return modules.single.name;
  return f.select<String?>(title, [
    if (allowAll) const SelectItem<String?>(null, 'All modules'),
    for (final m in modules)
      SelectItem<String?>(m.name, m.name,
          detail:
              '${f.rel(project.l10nDir(m))}  [${m.arbFiles.map((a) => a.locale).join(', ')}]'),
  ]);
}

Future<String> _pickKey(FlowContext f, String module, String title) async {
  final project = f.project;
  final m = project.module(module);
  final file = project.arbFile(m, project.defaultLocale);
  final data = file == null ? const <String, Object?>{} : readArb(file.path);
  final keys = data.keys.where(isTranslationKey).toList();
  if (keys.isEmpty) throw OpException('Module "$module" has no keys yet.');
  return f.select(
      title,
      [
        for (final k in keys) SelectItem(k, k, detail: '${data[k]}'),
      ],
      filterable: true);
}

String? _localeError(String v) => validateLocale(v);

// ─── Project ────────────────────────────────────────────────────────────────

Future<void> _doctor(FlowContext f) async {
  final items = diagnoseProject(f.root);
  final lines = <Line>[
    for (final i in items) ...[
      Line(
        '${switch (i.status) {
          DoctorStatus.ok => '✓',
          DoctorStatus.warning => '!',
          DoctorStatus.error => '✗'
        }} ${i.title}',
        switch (i.status) {
          DoctorStatus.ok => Tone.success,
          DoctorStatus.warning => Tone.warning,
          DoctorStatus.error => Tone.error,
        },
      ),
      if (i.detail != null)
        for (final d in i.detail!.split('\n')) Line('    $d', Tone.muted),
    ],
  ];
  final fixes = items.where((i) => i.fix != null).toList();
  if (fixes.isEmpty) {
    await f.show('Report', lines);
    return;
  }
  final chosen = await f.multiSelect<DoctorItem>(
    'Fixes',
    [for (final i in fixes) SelectItem(i, i.fixLabel!, detail: i.title)],
    help:
        'These problems can be fixed in pubspec.yaml. Space toggles, Enter applies.',
    selected: fixes.toSet(),
  );
  if (chosen.isEmpty) return;
  updateModularConfig(f.root, {for (final i in chosen) ...i.fix!});
  f.app.log('Updated pubspec.yaml.', Tone.success);
  f.app.generate();
  await _doctor(f);
}

Future<void> _init(FlowContext f) async {
  if (PubspecReader(f.root).readConfig() != null &&
      !await f.confirm('Already set up',
          details: const [
            Line('pubspec.yaml already has a modular_l10n section.'),
          ],
          yes: 'Set it up again')) {
    return;
  }
  final locale = await f.text('Default locale',
      help: 'The language your ARB templates are written in.',
      initial: 'en',
      validate: _localeError,
      suggestions: commonLocales);
  final module = await f.text('First module',
      help: 'snake_case, for example app, common, auth.',
      initial: 'app',
      validate: validateModuleName);
  final folder = await f.pickFolder('Where should "$module" live?',
      help: 'Its ARB files go in <folder>/l10n/. Create a new folder with n.');
  final className = await f.text('Generated class name',
      help: 'You will write <Class>.of(context).$module.… in widgets.',
      initial: 'ML',
      validate: validateClassName);
  if (!await f.confirm('Summary',
      details: [
        Line('default locale  ${normalizeLocale(locale)}'),
        Line('module          $module  →  ${f.rel(p.join(folder, 'l10n'))}/'),
        Line('class           $className'),
      ],
      yes: 'Set up')) {
    return;
  }
  await f.run(
      'Done',
      () => initProject(f.root,
          defaultLocale: locale,
          moduleName: module,
          moduleFolder: folder,
          className: className),
      summary:
          'Use $className.of(context).${toCamelCase(module)}.${starterKey(module)} in your widgets.');
}

Future<void> _settings(FlowContext f) async {
  while (true) {
    final c = loadConfig(f.root);
    final entries = <(String, String, Object?)>[
      ('enabled', 'Generation enabled', c.enabled),
      ('class_name', 'Class name', c.className),
      ('default_locale', 'Default locale', c.defaultLocale),
      ('output_dir', 'Output folder', c.outputDir),
      ('arb_dir_pattern', 'ARB file pattern', c.arbFilePattern),
      (
        'generate_combined_arb',
        'Combined ARB per locale',
        c.generateCombinedArb
      ),
      ('use_deferred_loading', 'Deferred loading (web)', c.useDeferredLoading),
      ('module_access', 'Module access', c.moduleAccess.name),
      ('log_level', 'Log level', c.logLevel.name),
    ];
    final key = await f.select(
        'Settings',
        [
          for (final (k, label, value) in entries)
            SelectItem(k, label.padRight(26), detail: '$value'),
        ],
        help:
            'Saved to the modular_l10n section of pubspec.yaml. Esc when done.');
    final current = entries.firstWhere((e) => e.$1 == key).$3;
    final Object value = switch (key) {
      'enabled' ||
      'generate_combined_arb' ||
      'use_deferred_loading' =>
        !(current as bool),
      'module_access' => await f.select('Module access', const [
          SelectItem('part', 'part',
              detail: 'modules are reachable only through the entry point'),
          SelectItem('library', 'library',
              detail: 'module files can be imported directly'),
        ]),
      'log_level' => await f.select('Log level', [
          for (final l in LogLevel.values) SelectItem(l.name, l.name),
        ]),
      'class_name' => await f.text('Class name',
          initial: '$current', validate: validateClassName),
      'default_locale' => normalizeLocale(await f.text('Default locale',
          initial: '$current',
          validate: _localeError,
          suggestions: f.project.locales)),
      _ => await f.text(entries.firstWhere((e) => e.$1 == key).$2,
          initial: '$current'),
    };
    updateModularConfig(f.root, {key: value});
    f.app.log('Set modular_l10n.$key to $value.', Tone.success);
    f.app.generate();
  }
}

// ─── Modules & keys ─────────────────────────────────────────────────────────

Future<void> _createModule(FlowContext f) async {
  final project = f.project;
  final folder = await f.pickFolder('Pick the feature folder',
      help:
          'The module\'s ARB files go in <folder>/l10n/. Folders marked [l10n] already have one.');
  final existing = project.modules
      .where((m) => p.equals(project.l10nDir(m), p.join(folder, 'l10n')))
      .firstOrNull;
  final name = existing?.name ??
      await f.text('Module name',
          help:
              'snake_case. You will use it as .${toCamelCase(suggestModuleName(folder))} in code.',
          initial: suggestModuleName(folder),
          validate: validateModuleName);
  final known =
      project.locales.isEmpty ? [project.defaultLocale] : project.locales;
  var locales = (await f.multiSelect(
          'Locales',
          [
            for (final l in known)
              SelectItem(l, l,
                  detail: l == project.defaultLocale ? 'default' : null),
            const SelectItem('+', '+ another locale…'),
          ],
          selected: known.toSet()))
      .toList();
  if (locales.remove('+')) {
    final extra = await f.text('More locales',
        help: 'Comma-separated, for example fr, de.', validate: (v) {
      try {
        parseLocaleList(v);
        return null;
      } on OpException catch (e) {
        return e.message;
      }
    }, suggestions: commonLocales);
    locales = {...locales, ...parseLocaleList(extra)}.toList();
  }
  if (locales.isEmpty) throw OpException('Choose at least one locale.');
  await f.run('Module created',
      () => createModule(project, folder: folder, name: name, locales: locales),
      summary:
          'Module "$name" → ${project.config.className}.of(context).${toCamelCase(name)}');
}

Future<void> _addKey(FlowContext f) async {
  final project = f.project;
  final module = (await _pickModule(f, 'Add to which module?'))!;
  final existing = moduleKeys(project, module).toSet();
  final key = await f.text('Key name',
      help: 'camelCase, for example welcomeMessage.',
      validate: (v) =>
          validateKeyName(v) ??
          (existing.contains(v) ? 'Key "$v" already exists.' : null));
  final m = project.module(module);
  final files = [...m.arbFiles]
    ..sort((a, b) => a.locale == project.defaultLocale
        ? -1
        : b.locale == project.defaultLocale
            ? 1
            : 0);
  final values = <String, String>{};
  for (final file in files) {
    values[file.locale] = await f.text('Text in ${file.locale}',
        help: file.locale == project.defaultLocale
            ? 'ICU syntax works: Hello {name}, {count, plural, one{# item} other{# items}}'
            : 'Template: ${values[project.defaultLocale] ?? ''}  (leave empty to translate later)',
        allowEmpty: file.locale != project.defaultLocale);
  }
  await f.run('Key added',
      () => addKey(project, module: module, key: key, values: values),
      summary:
          'Use ${project.config.className}.of(context).${toCamelCase(module)}.$key');
}

Future<void> _translate(FlowContext f) async {
  final project = f.project;
  final targets =
      project.locales.where((l) => l != project.defaultLocale).toList();
  if (targets.isEmpty) throw OpException('Add a second locale first.');
  final locale = await f.select('Translate into', [
    for (final l in targets)
      SelectItem(l, l, detail: '${untranslatedKeys(project, l).length} to do'),
  ]);
  final todo = untranslatedKeys(project, locale);
  var done = 0;
  for (final (i, item) in todo.indexed) {
    final String value;
    try {
      value = await f.text(
          '${item.module}.${item.key}  (${i + 1}/${todo.length})',
          help:
              '${project.defaultLocale}: ${item.template}   — empty skips, Esc stops',
          allowEmpty: true);
    } on FlowCancelled {
      break;
    }
    if (value.isEmpty) continue;
    setTranslation(f.app.requireProject,
        module: item.module, locale: locale, key: item.key, value: value);
    done++;
  }
  f.app.log('Translated $done key(s) into $locale.', Tone.success);
  if (done > 0) f.app.generate();
  await f.show('Done', [
    Line('Translated $done of ${todo.length} key(s) into $locale.',
        Tone.success),
  ]);
}

Future<void> _renameKey(FlowContext f) async {
  final project = f.project;
  final module = (await _pickModule(f, 'Which module?'))!;
  final oldKey = await _pickKey(f, module, 'Which key?');
  final keys = moduleKeys(project, module).toSet();
  final newKey = await f.text('New name for "$oldKey"',
      initial: oldKey,
      validate: (v) =>
          validateKeyName(v) ??
          (v == oldKey
              ? 'That is the current name.'
              : keys.contains(v)
                  ? 'Key "$v" already exists.'
                  : null));
  final preview = renameKey(project,
      module: module, oldKey: oldKey, newKey: newKey, dryRun: true);
  if (!await f.confirm('Preview',
      details: [
        for (final file in preview.result.changed)
          Line(
              '  ${f.rel(file)}${switch (preview.dartEdits.where((e) => e.path == file).firstOrNull) {
            final e? => '  (line ${e.lines.join(', ')})',
            null => '',
          }}'),
      ],
      yes: 'Rename')) {
    return;
  }
  await f.run(
      'Renamed',
      () => renameKey(project, module: module, oldKey: oldKey, newKey: newKey)
          .result);
}

// ─── Locales ────────────────────────────────────────────────────────────────

Future<void> _addLocale(FlowContext f) async {
  final project = f.project;
  final locale = await f.text('Locale to add',
      help:
          'Language code, optionally with script or region: fr, pt_BR, zh_Hans. Tab cycles suggestions.',
      validate: (v) =>
          _localeError(v) ??
          (project.locales.contains(normalizeLocale(v))
              ? 'The project already has "$v".'
              : null),
      suggestions:
          commonLocales.where((l) => !project.locales.contains(l)).toList());
  await f.run('Locale added', () => addLocale(project, locale),
      summary:
          'Added ${normalizeLocale(locale)}. Use Translate to fill it in.');
}

Future<void> _removeLocale(FlowContext f) async {
  final project = f.project;
  final removable =
      project.locales.where((l) => l != project.defaultLocale).toList();
  if (removable.isEmpty) throw OpException('Only the default locale exists.');
  final locale = await f.select('Remove which locale?', [
    for (final l in removable) SelectItem(l, l),
  ]);
  final files = filesForLocale(project, locale);
  if (!await f.confirm('Delete ${files.length} file(s)',
      details: [
        for (final file in files) Line('  ${f.rel(file)}', Tone.warning),
      ],
      yes: 'Delete',
      danger: true)) {
    return;
  }
  await f.run('Locale removed', () => removeLocale(project, locale));
}

Future<void> _pseudo(FlowContext f) async {
  final locale = await f.text('Pseudo-locale code',
      initial: 'en_XA', validate: _localeError);
  final expansion = await f.select('Text expansion', const [
    SelectItem(0.3, 'Normal', detail: '~30% longer, like German or French'),
    SelectItem(0.5, 'Long', detail: '~50% longer'),
    SelectItem(0.0, 'None', detail: 'accents only'),
  ]);
  await f.run(
      'Pseudo-locale',
      () =>
          generatePseudoLocale(f.project, locale: locale, expansion: expansion),
      summary: 'Run the app in ${normalizeLocale(locale)} to see it.');
}

// ─── Quality ────────────────────────────────────────────────────────────────

Future<void> _check(FlowContext f) async {
  while (true) {
    final project = f.project;
    final issues = checkProject(project, hints: true);
    if (issues.isEmpty) {
      await f.show('Check', const [Line('✓ No problems found.', Tone.success)]);
      return;
    }
    final errors =
        issues.where((i) => i.severity == IssueSeverity.error).length;
    final warnings =
        issues.where((i) => i.severity == IssueSeverity.warning).length;
    final issue = await f.select<Issue>(
      '$errors error(s), $warnings warning(s)',
      [
        for (final i in issues)
          SelectItem(
              i,
              '${switch (i.severity) {
                IssueSeverity.error => '✗',
                IssueSeverity.warning => '!',
                IssueSeverity.info => '·'
              }} '
              '${i.module == null ? '' : '[${i.module}${i.locale == null ? '' : ' ${i.locale}'}] '}${i.message}',
              detail: i.file == null
                  ? null
                  : '${f.rel(i.file!)}${i.line == null ? '' : ':${i.line}'}'),
      ],
      help:
          'Enter on a missing or empty translation to fill it in. Esc closes.',
      filterable: true,
    );
    final canEdit = (issue.code == 'missing-translation' ||
            issue.code == 'empty-translation') &&
        issue.module != null &&
        issue.locale != null &&
        issue.key != null;
    if (!canEdit) {
      await f.show(issue.code, [
        Line(issue.message),
        if (issue.file != null)
          Line(
              '${f.rel(issue.file!)}${issue.line == null ? '' : ':${issue.line}'}',
              Tone.muted),
      ]);
      continue;
    }
    final template =
        project.arbFile(project.module(issue.module!), project.defaultLocale);
    final source =
        template == null ? '' : '${readArb(template.path)[issue.key]}';
    final value = await f.text(
        '${issue.module}.${issue.key} in ${issue.locale}',
        help: '${project.defaultLocale}: $source');
    setTranslation(project,
        module: issue.module!,
        locale: issue.locale!,
        key: issue.key!,
        value: value);
    f.app.generate();
  }
}

Future<void> _hardcoded(FlowContext f) async {
  while (true) {
    final project = f.project;
    final found = scanHardcodedStrings(project);
    if (found.isEmpty) {
      await f.show('Hardcoded strings',
          const [Line('✓ No hardcoded UI strings found.', Tone.success)]);
      return;
    }
    final s = await f.select<HardcodedString>(
        '${found.length} hardcoded string(s)',
        [
          for (final s in found)
            SelectItem(s, s.literal, detail: '${f.rel(s.file)}:${s.line}'),
        ],
        help: 'Enter extracts the string into an ARB file. Esc closes.',
        filterable: true);
    final plan = planExtract(s.file, s.line, s.column);
    final module =
        (await _pickModule(f, 'Move "${plan.arbValue}" into which module?'))!;
    final existing = moduleKeys(project, module).toSet();
    final key = await f.text('Key name',
        initial: plan.suggestedKey,
        validate: (v) =>
            validateKeyName(v) ??
            (existing.contains(v) ? 'Key "$v" already exists.' : null));
    final call =
        '${project.config.className}.of(context).${toCamelCase(module)}.$key'
        '${plan.placeholders.isEmpty ? '' : '(${plan.placeholders.join(', ')})'}';
    if (!await f.confirm('Preview',
        details: [
          Line('${f.rel(s.file)}:${s.line}', Tone.muted),
          Line('- ${s.context}', Tone.error),
          Line('+ ${s.context.replaceFirst(plan.literal, call)}', Tone.success),
          const Line(''),
          Line('${project.defaultLocale}: "$key": "${plan.arbValue}"'),
        ],
        yes: 'Extract')) {
      continue;
    }
    await f.run('Extracted',
        () => extractString(project, plan, module: module, key: key));
  }
}

Future<void> _unused(FlowContext f) async {
  final project = f.project;
  final unused = findUnusedKeys(project);
  final items = [
    for (final MapEntry(key: module, value: keys) in unused.entries)
      for (final key in keys) SelectItem((module, key), '$module.$key'),
  ];
  if (items.isEmpty) {
    await f.show('Unused keys',
        const [Line('✓ Every key is referenced in lib/.', Tone.success)]);
    return;
  }
  final chosen = await f.multiSelect(
      '${items.length} possibly unused key(s)', items,
      help:
          'Keys used dynamically show up here too. Pick the ones to delete, then Enter.');
  if (chosen.isEmpty) return;
  final byModule = <String, List<String>>{};
  for (final (module, key) in chosen) {
    byModule.putIfAbsent(module, () => []).add(key);
  }
  if (!await f.confirm('Remove ${chosen.length} key(s) from every locale',
      yes: 'Remove', danger: true)) {
    return;
  }
  await f.run('Removed', () => removeKeys(project, byModule));
}

// ─── Exchange ───────────────────────────────────────────────────────────────

Future<void> _export(FlowContext f) async {
  final project = f.project;
  final format = await f.select('Format', const [
    SelectItem(ExchangeFormat.csv, 'CSV',
        detail: 'Excel, Google Sheets, Numbers'),
    SelectItem(ExchangeFormat.xliff, 'XLIFF 1.2',
        detail: 'Crowdin, Lokalise, Phrase, Trados…'),
  ]);
  final module = await _pickModule(f, 'Which modules?', allowAll: true);
  final folder = await f.pickFolder('Save in which folder?',
      action: 'Save here', start: f.root);
  final name = await f.text('File name',
      initial: 'translations.${format == ExchangeFormat.csv ? 'csv' : 'xlf'}');
  final path = p.join(folder, name);
  final count = exportTranslations(project,
      outputPath: path, format: format, module: module);
  f.app.log('Exported $count key(s) to ${f.rel(path)}.', Tone.success);
  await f.show('Exported',
      [Line('Exported $count key(s) to ${f.rel(path)}.', Tone.success)]);
}

Future<void> _import(FlowContext f) async {
  final project = f.project;
  final files = <String>[];
  void walk(String dir, int depth) {
    if (depth > 4) return;
    for (final e in Directory(dir).listSync()) {
      final name = p.basename(e.path);
      if (name.startsWith('.') || name == 'build') continue;
      if (e is Directory) walk(e.path, depth + 1);
      if (e is File && RegExp(r'\.(csv|xlf|xliff)$').hasMatch(name)) {
        files.add(e.path);
      }
    }
  }

  walk(f.root, 0);
  if (files.isEmpty) {
    throw OpException(
        'No .csv, .xlf or .xliff file in the project. Put the file in the project folder first.');
  }
  final file = await f.select('Import which file?', [
    for (final path in files) SelectItem(path, f.rel(path)),
  ]);
  final preview = importTranslations(project, file, dryRun: true);
  if (preview.changes.isEmpty) {
    await f.show('Nothing to import', [
      const Line(
          'No translation in the file differs from the ARB files.', Tone.muted),
      for (final s in preview.skipped) Line('skipped $s', Tone.warning),
    ]);
    return;
  }
  if (!await f.confirm('${preview.changes.length} change(s)',
      details: [
        for (final c in preview.changes.take(200))
          Line('${c.module}.${c.key} [${c.locale}]: "${c.newValue}"'),
        if (preview.changes.length > 200)
          Line('… and ${preview.changes.length - 200} more', Tone.muted),
        for (final s in preview.skipped) Line('skipped $s', Tone.warning),
      ],
      yes: 'Import')) {
    return;
  }
  await f.run('Imported', () => importTranslations(project, file).files);
}

Future<void> _migrate(FlowContext f) async {
  final project = f.project;
  final files = findFlutterIntlArbs(f.root);
  if (files.isEmpty) throw OpException('No intl_*.arb files in lib/l10n.');
  final mode = await f.select(
      '${files.length} Flutter Intl file(s): ${files.map((x) => x.locale).join(', ')}',
      const [
        SelectItem('single', 'One module',
            detail: 'every key goes into one module'),
        SelectItem('prefix', 'Split by prefix',
            detail: 'authLogin → auth, homeTitle → home'),
      ]);
  if (mode == 'single') {
    final module = await f.text('Module name',
        initial: 'app', validate: validateModuleName);
    final folder = await f.pickFolder('Where should "$module" live?');
    await f.run(
        'Migrated',
        () => migrateFromFlutterIntl(project,
            files: files, module: module, folder: folder));
    return;
  }
  final prefixes = countPrefixes(files);
  final base = await f.pickFolder('Base folder for the new modules',
      help: 'Each prefix gets <folder>/<prefix>/l10n/.',
      action: 'Use this folder');
  if (!await f.confirm('Modules to create',
      details: [
        for (final MapEntry(:key, :value) in prefixes.entries)
          Line(
              '  $key  ($value key(s))  →  ${f.rel(p.join(base, key, 'l10n'))}/'),
      ],
      yes: 'Create')) {
    return;
  }
  await f.run('Migrated',
      () => migrateFromFlutterIntl(project, files: files, baseFolder: base));
}
