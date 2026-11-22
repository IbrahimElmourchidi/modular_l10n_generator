/// Pseudo-locales, CSV/XLIFF export and import, and migration from
/// Flutter Intl.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../config.dart';
import 'arb_file.dart';
import 'module_ops.dart' show validateLocale;
import 'project.dart';

// ─── Pseudo-locale ──────────────────────────────────────────────────────────

const _pseudoChars = {
  'a': 'å', 'b': 'ƀ', 'c': 'ç', 'd': 'ð', 'e': 'ë', 'f': 'ƒ', //
  'g': 'ğ', 'h': 'ĥ', 'i': 'ï', 'j': 'ĵ', 'k': 'ĸ', 'l': 'ĺ',
  'm': 'ɱ', 'n': 'ñ', 'o': 'ö', 'p': 'þ', 'q': 'ǫ', 'r': 'ř',
  's': 'š', 't': 'ţ', 'u': 'ü', 'v': 'ṽ', 'w': 'ŵ', 'x': 'ẋ',
  'y': 'ÿ', 'z': 'ž',
  'A': 'Å', 'B': 'Ɓ', 'C': 'Ç', 'D': 'Ð', 'E': 'Ë', 'F': 'Ƒ',
  'G': 'Ğ', 'H': 'Ĥ', 'I': 'Ï', 'J': 'Ĵ', 'K': 'Ķ', 'L': 'Ĺ',
  'M': 'Ṁ', 'N': 'Ñ', 'O': 'Ö', 'P': 'Þ', 'Q': 'Ǫ', 'R': 'Ř',
  'S': 'Š', 'T': 'Ţ', 'U': 'Ü', 'V': 'Ṽ', 'W': 'Ŵ', 'X': 'Ẋ',
  'Y': 'Ÿ', 'Z': 'Ž',
};

/// Accented, padded and bracketed text, so untranslated strings, clipped
/// layouts and concatenation bugs stand out. `{…}` blocks are kept as is.
String pseudoLocalize(String text, double expansion) {
  final out = StringBuffer();
  var i = 0;
  while (i < text.length) {
    if (text[i] == '{') {
      var depth = 1, j = i + 1;
      while (j < text.length && depth > 0) {
        if (text[j] == '{') depth++;
        if (text[j] == '}') depth--;
        j++;
      }
      out.write(text.substring(i, j));
      i = j;
      continue;
    }
    if (text[i] == r'\' && i + 1 < text.length) {
      out.write(text.substring(i, i + 2));
      i += 2;
      continue;
    }
    out.write(_pseudoChars[text[i]] ?? text[i]);
    i++;
  }
  var result = out.toString();
  if (expansion > 0) {
    result = '$result ${'~' * (result.length * expansion).ceil()}';
  }
  return '[$result]';
}

/// Write a pseudo-locale file next to each module's default-locale file.
OpResult generatePseudoLocale(
  Project project, {
  String locale = 'en_XA',
  double expansion = 0.3,
  DateTime? today,
}) {
  final error = validateLocale(locale);
  if (error != null) throw OpException(error);
  final pseudo = normalizeLocale(locale);
  if (pseudo == project.defaultLocale) {
    throw OpException('The pseudo-locale cannot be the default locale.');
  }
  final result = OpResult();
  for (final module in project.modules) {
    final source = project.arbFile(module, project.defaultLocale);
    if (source == null) continue;
    final data = readArb(source.path);
    final out = <String, Object?>{
      '@@locale': pseudo,
      '@@context': data['@@context'],
      if (data['@@last_modified'] != null)
        '@@last_modified':
            (today ?? DateTime.now()).toIso8601String().split('T').first,
    };
    for (final key in data.keys.where(isTranslationKey)) {
      final value = data[key];
      out[key] = value is String ? pseudoLocalize(value, expansion) : value;
      if (data['@$key'] != null) out['@$key'] = data['@$key'];
    }
    final existing = project.arbFile(module, pseudo)?.path;
    final path = existing ??
        p.join(p.dirname(source.path), arbFileName(module.name, pseudo));
    final existed = File(path).existsSync();
    if (writeArb(path, out)) {
      (existed ? result.changed : result.created).add(path);
    }
  }
  return result;
}

// ─── Export ─────────────────────────────────────────────────────────────────

enum ExchangeFormat { csv, xliff }

ExchangeFormat formatOfPath(String path) {
  final ext = p.extension(path).toLowerCase();
  return switch (ext) {
    '.csv' => ExchangeFormat.csv,
    '.xlf' || '.xliff' => ExchangeFormat.xliff,
    _ =>
      throw OpException('Unknown file type "$ext": use .csv, .xlf or .xliff.'),
  };
}

/// Module → locale → ARB data, for the selected modules.
Map<String, Map<String, Map<String, Object?>>> _load(
        Project project, String? module) =>
    {
      for (final m
          in module == null ? project.modules : [project.module(module)])
        m.name: {
          for (final f in m.arbFiles) f.locale: readArb(f.path),
        },
    };

/// Export translations to [outputPath] as CSV
/// (`Module,Key,Description,<locales…>`, UTF-8 with BOM, for Excel) or
/// XLIFF 1.2 (one `<file>` per non-default locale). Returns the number of
/// keys (CSV rows or XLIFF units) written.
int exportTranslations(
  Project project, {
  required String outputPath,
  ExchangeFormat? format,
  String? module,
}) {
  format ??= formatOfPath(outputPath);
  final data = _load(project, module);
  final template = project.defaultLocale;
  final locales = project.locales;
  var count = 0;
  final out = StringBuffer();

  if (format == ExchangeFormat.csv) {
    final rows = <List<String>>[
      ['Module', 'Key', 'Description', ...locales],
    ];
    for (final MapEntry(key: name, value: byLocale) in data.entries) {
      final base = byLocale[template] ?? const {};
      for (final key in base.keys.where(isTranslationKey)) {
        final meta = base['@$key'];
        rows.add([
          name,
          key,
          meta is Map && meta['description'] is String
              ? meta['description'] as String
              : '',
          for (final l in locales)
            byLocale[l]?[key] == null ? '' : '${byLocale[l]![key]}',
        ]);
        count++;
      }
    }
    out
      ..write('\uFEFF')
      ..write(rows.map((r) => r.map(_csvCell).join(',')).join('\n'));
  } else {
    out
      ..write('<?xml version="1.0" encoding="UTF-8"?>\n')
      ..write(
          '<xliff version="1.2" xmlns="urn:oasis:names:tc:xliff:document:1.2">\n');
    for (final target in locales.where((l) => l != template)) {
      out
        ..write('  <file source-language="$template" target-language="$target" '
            'datatype="plaintext" original="modular_l10n">\n')
        ..write('    <body>\n');
      for (final MapEntry(key: name, value: byLocale) in data.entries) {
        final base = byLocale[template];
        if (base == null) continue;
        final translated = byLocale[target] ?? const {};
        for (final key in base.keys.where(isTranslationKey)) {
          final meta = base['@$key'];
          final note = meta is Map && meta['description'] != null
              ? '\n        <note>${_xml('${meta['description']}')}</note>'
              : '';
          out
            ..write('      <trans-unit id="$name.$key" resname="$key">$note\n')
            ..write('        <source>${_xml('${base[key] ?? ''}')}</source>\n')
            ..write(
                '        <target>${_xml('${translated[key] ?? ''}')}</target>\n')
            ..write('      </trans-unit>\n');
          count++;
        }
      }
      out
        ..write('    </body>\n')
        ..write('  </file>\n');
    }
    out.write('</xliff>\n');
  }

  File(outputPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(out.toString());
  return count;
}

String _csvCell(String cell) => cell.contains(',') ||
        cell.contains('"') ||
        cell.contains('\n') ||
        cell.contains('\r')
    ? '"${cell.replaceAll('"', '""')}"'
    : cell;

String _xml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _unXml(String text) => text
    .replaceAll('&apos;', "'")
    .replaceAll('&quot;', '"')
    .replaceAll('&gt;', '>')
    .replaceAll('&lt;', '<')
    .replaceAll('&amp;', '&');

// ─── Import ─────────────────────────────────────────────────────────────────

/// One translation an import would write.
class ImportChange {
  const ImportChange(
      this.module, this.locale, this.key, this.oldValue, this.newValue);
  final String module;
  final String locale;
  final String key;
  final Object? oldValue;
  final String newValue;
}

/// The outcome of [importTranslations].
class ImportResult {
  final List<ImportChange> changes = [];

  /// Rows or units that could not be applied, with the reason.
  final List<String> skipped = [];
  final OpResult files = OpResult();
}

/// Read translations from a CSV or XLIFF file into the existing ARB files.
///
/// Only keys that exist in the module's default-locale file are imported,
/// and empty cells or targets are ignored, so a partial spreadsheet never
/// erases work. With [dryRun], nothing is written.
ImportResult importTranslations(Project project, String inputPath,
    {bool dryRun = false}) {
  final file = File(inputPath);
  if (!file.existsSync()) throw OpException('File not found: $inputPath');
  final entries = switch (formatOfPath(inputPath)) {
    ExchangeFormat.csv => _readCsv(file.readAsStringSync()),
    ExchangeFormat.xliff => _readXliff(file.readAsStringSync()),
  };

  final result = ImportResult();
  final pending = <String, Map<String, Object?>>{};
  for (final (:module, :locale, :key, :value) in entries) {
    if (value.isEmpty) continue;
    final m = project.modules.where((m) => m.name == module).firstOrNull;
    if (m == null) {
      result.skipped.add('$module.$key: no module "$module"');
      continue;
    }
    final canonical = normalizeLocale(locale);
    final target = project.arbFile(m, canonical);
    if (target == null) {
      result.skipped.add('$module.$key: module has no "$canonical" file');
      continue;
    }
    final template = project.arbFile(m, project.defaultLocale);
    final templateData = template == null
        ? const <String, Object?>{}
        : pending[template.path] ?? readArb(template.path);
    if (!templateData.containsKey(key)) {
      result.skipped.add('$module.$key: not a key of the module');
      continue;
    }
    final data = pending.putIfAbsent(target.path, () => readArb(target.path));
    if (data[key] == value) continue;
    result.changes.add(ImportChange(module, canonical, key, data[key], value));
    data[key] = value;
  }

  if (!dryRun) {
    for (final MapEntry(key: path, value: data) in pending.entries) {
      if (writeArb(path, data)) result.files.changed.add(path);
    }
  }
  return result;
}

typedef _Entry = ({String module, String locale, String key, String value});

List<_Entry> _readCsv(String content) {
  final rows =
      parseCsv(content.startsWith('\uFEFF') ? content.substring(1) : content);
  if (rows.length < 2) return const [];
  final header = rows.first;
  if (header.length < 4 || header[0] != 'Module' || header[1] != 'Key') {
    throw OpException(
        'The CSV must start with the columns Module,Key,Description,<locales…> '
        '(the layout "export" writes).');
  }
  final locales = header.sublist(3);
  return [
    for (final row in rows.skip(1))
      if (row.length >= 4)
        for (var j = 0; j < locales.length && j + 3 < row.length; j++)
          (module: row[0], locale: locales[j], key: row[1], value: row[j + 3]),
  ];
}

/// RFC 4180 CSV parsing: quoted fields, doubled quotes, CRLF or LF.
List<List<String>> parseCsv(String content) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < content.length; i++) {
    final ch = content[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < content.length && content[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n' || ch == '\r') {
      row.add(field.toString());
      field.clear();
      if (row.any((f) => f.isNotEmpty)) rows.add(row);
      row = [];
      if (ch == '\r' && i + 1 < content.length && content[i + 1] == '\n') i++;
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    if (row.any((f) => f.isNotEmpty)) rows.add(row);
  }
  return rows;
}

final _xliffFile =
    RegExp(r'<file[^>]*target-language="([^"]*)"[^>]*>([\s\S]*?)</file>');
final _xliffUnit = RegExp(
    r'<trans-unit[^>]*id="([^"]*)"[^>]*>[\s\S]*?<target(?:\s[^>]*)?>([\s\S]*?)</target>[\s\S]*?</trans-unit>');

List<_Entry> _readXliff(String content) => [
      for (final f in _xliffFile.allMatches(content))
        for (final u in _xliffUnit.allMatches(f[2]!))
          if (u[1]!.contains('.'))
            (
              module: u[1]!.substring(0, u[1]!.indexOf('.')),
              locale: f[1]!,
              key: u[1]!.substring(u[1]!.indexOf('.') + 1),
              value: _unXml(u[2]!),
            ),
    ];

// ─── Migration from Flutter Intl ────────────────────────────────────────────

/// A Flutter Intl ARB file and the locale it holds.
typedef IntlArb = ({String path, String locale, Map<String, Object?> data});

/// The `intl_*.arb` files in [dir] (Flutter Intl's `lib/l10n` by default).
List<IntlArb> findFlutterIntlArbs(String rootPath, {String? dir}) {
  final folder = Directory(p.join(rootPath, dir ?? p.join('lib', 'l10n')));
  if (!folder.existsSync()) return const [];
  final files = folder
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'^intl_.+\.arb$').hasMatch(p.basename(f.path)))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      (
        path: f.path,
        locale: normalizeLocale(switch (readArb(f.path)['@@locale']) {
          final String l when l.isNotEmpty => l,
          _ => p.basenameWithoutExtension(f.path).substring('intl_'.length),
        }),
        data: readArb(f.path),
      ),
  ];
}

final _prefix = RegExp(r'^([a-z]+)[A-Z]');

/// The module a key goes to when splitting by prefix: `authLogin` → `auth`,
/// keys without a camelCase prefix → `common`.
String prefixOf(String key) => _prefix.firstMatch(key)?[1] ?? 'common';

/// Prefix → number of keys, from the first file, largest first.
Map<String, int> countPrefixes(List<IntlArb> files) {
  final counts = <String, int>{};
  if (files.isEmpty) return counts;
  for (final key in files.first.data.keys.where(isTranslationKey)) {
    counts.update(prefixOf(key), (n) => n + 1, ifAbsent: () => 1);
  }
  return Map.fromEntries(
      counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
}

/// Move Flutter Intl ARB files into modules.
///
/// With [module] set, every file becomes one module in [folder]. Otherwise
/// keys are split by camelCase prefix into `<baseFolder>/<prefix>/l10n/`.
/// The original files are left alone; existing module files are skipped
/// unless [overwrite].
OpResult migrateFromFlutterIntl(
  Project project, {
  required List<IntlArb> files,
  String? module,
  String? folder,
  String? baseFolder,
  bool overwrite = false,
}) {
  if (files.isEmpty) throw OpException('No intl_*.arb files found.');
  final result = OpResult();

  void write(String path, Map<String, Object?> data) {
    final exists = File(path).existsSync();
    if (exists && !overwrite) {
      result.skipped.add('${project.relative(path)} (already exists)');
      return;
    }
    writeArb(path, data);
    (exists ? result.changed : result.created).add(path);
  }

  if (module != null) {
    final error = validateModuleName(module);
    if (error != null) throw OpException(error);
    final dir = p.join(
        p.absolute(
            folder ?? p.join(project.rootPath, 'lib', 'features', module)),
        'l10n');
    for (final f in files) {
      write(p.join(dir, arbFileName(module, f.locale)), {
        '@@locale': f.locale,
        '@@context': module,
        for (final MapEntry(:key, :value) in f.data.entries)
          if (key != '@@locale' && key != '@@context') key: value,
      });
    }
    return result;
  }

  final base =
      p.absolute(baseFolder ?? p.join(project.rootPath, 'lib', 'features'));
  for (final f in files) {
    final groups = <String, Map<String, Object?>>{};
    for (final MapEntry(:key, :value) in f.data.entries) {
      if (!isTranslationKey(key)) continue;
      final prefix = prefixOf(key);
      final group = groups.putIfAbsent(
          prefix, () => {'@@locale': f.locale, '@@context': prefix});
      group[key] = value;
      if (f.data.containsKey('@$key')) group['@$key'] = f.data['@$key'];
    }
    for (final MapEntry(key: prefix, value: data) in groups.entries) {
      write(p.join(base, prefix, 'l10n', arbFileName(prefix, f.locale)), data);
    }
  }
  return result;
}
