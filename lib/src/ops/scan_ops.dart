/// Finding hardcoded UI strings in Dart code and extracting them into ARB
/// files. The heuristics are the VS Code extension's, line based: a line must
/// look like UI code and must not look like a route, asset, key, log call…
library;

import 'dart:io';

import '../dart_generator.dart' show toCamelCase;
import 'arb_file.dart';
import 'project.dart';

/// A string literal that looks like user-facing text.
class HardcodedString {
  const HardcodedString({
    required this.file,
    required this.line,
    required this.column,
    required this.literal,
    required this.context,
  });

  final String file;

  /// 1-based line.
  final int line;

  /// 0-based column of the opening quote.
  final int column;

  /// The literal as written, quotes included.
  final String literal;

  /// The trimmed source line.
  final String context;
}

final _uiPatterns = [
  RegExp(r'''Text\s*\(\s*(['"])'''),
  RegExp(r'Text\.rich\s*\('),
  RegExp(r'''TextSpan\s*\(\s*text\s*:\s*(['"])'''),
  RegExp(r'RichText\s*\('),
  RegExp(
      r'''(?:label|hint|helper|error|title|subtitle|message|content|description|tooltip|placeholder|semantics)\s*(?:Text)?\s*:\s*(['"])''',
      caseSensitive: false),
  RegExp(r'''AppBar\s*\(\s*title\s*:\s*Text\s*\(\s*(['"])'''),
  RegExp(r'''showDialog[^)]*title\s*:\s*Text\s*\(\s*(['"])'''),
  RegExp(r'''AlertDialog\s*\([^)]*title\s*:\s*Text\s*\(\s*(['"])'''),
  RegExp(r'''SnackBar\s*\(\s*content\s*:\s*Text\s*\(\s*(['"])'''),
  RegExp(r'ScaffoldMessenger[^)]*showSnackBar'),
  RegExp(
      r'''(?:Elevated|Text|Outlined|Filled)Button\s*\([^)]*child\s*:\s*Text\s*\(\s*(['"])'''),
  RegExp(
      r'''InputDecoration\s*\([^)]*(?:label|hint|helper|error|prefix|suffix|counter)Text\s*:\s*(['"])'''),
  RegExp(r'''Tab\s*\(\s*text\s*:\s*(['"])'''),
  RegExp(r'''BottomNavigationBarItem\s*\([^)]*label\s*:\s*(['"])'''),
  RegExp(r'''ListTile\s*\([^)]*title\s*:\s*Text\s*\(\s*(['"])'''),
  RegExp(r'''ListTile\s*\([^)]*subtitle\s*:\s*Text\s*\(\s*(['"])'''),
];

final _excludePatterns = [
  RegExp(r'^import\s+'),
  RegExp(r'^export\s+'),
  RegExp(r'^part\s+'),
  RegExp(r'''(?:route|path|navigate|push|pop)\s*[\(:]\s*['"][\w\/\-:]+['"]''',
      caseSensitive: false),
  RegExp(r'''(?:asset|image|icon|font)\s*[\(:]\s*['"][\w\/\-\.]+['"]''',
      caseSensitive: false),
  RegExp(r'''['"](?:assets|images|icons|fonts)\/'''),
  RegExp(r'''['"]packages?\/'''),
  RegExp(r'''(?:key|id|tag|hero)\s*:\s*['"][\w\-]+['"]''',
      caseSensitive: false),
  RegExp(r'''Key\s*\(\s*['"][\w\-]+['"]\s*\)'''),
  RegExp(r'''['"]https?:\/\/'''),
  RegExp(r'''['"]\s*.\s*['"]'''),
  RegExp(r'''['"]["']'''),
  RegExp(r'''['"][\w\.]+\/[\w\.]+['"]'''),
  RegExp(r'^@\w+'),
  RegExp(r'(?:print|debugPrint|log|logger)\s*\(', caseSensitive: false),
  RegExp(r'^\s*\/\/'),
  RegExp(r'^\s*\/\*'),
  RegExp(r'^\s*\*'),
  RegExp(r'''['"]\s*[\+\$]\s*'''),
  RegExp(r'''MethodChannel\s*\(\s*['"]'''),
  RegExp(r'''EventChannel\s*\(\s*['"]'''),
  RegExp(r'''RegExp\s*\(\s*['"]'''),
  RegExp(r'''\[\s*['"][\w]+['"]\s*\]'''),
];

final _identifierLike = RegExp(r'^[\w\/\.\-:]+$');
final _hexColor = RegExp(r'^#[0-9a-fA-F]+$');

/// Hardcoded UI strings in the app's Dart files.
List<HardcodedString> scanHardcodedStrings(Project project) => [
      for (final file in project.dartSourceFiles()) ...scanDartFile(file),
    ];

/// Hardcoded UI strings in one Dart file.
List<HardcodedString> scanDartFile(String path) {
  final List<String> lines;
  try {
    lines = File(path).readAsStringSync().split('\n');
  } on FileSystemException {
    return const [];
  }
  final results = <HardcodedString>[];
  for (var n = 0; n < lines.length; n++) {
    final line = lines[n];
    final trimmed = line.trim();
    if (_excludePatterns.any((p) => p.hasMatch(trimmed))) continue;
    if (!_uiPatterns.any((p) => p.hasMatch(line))) continue;
    for (final (:start, :text) in stringLiteralsOnLine(line)) {
      final content = text.substring(1, text.length - 1);
      if (content.length < 2) continue;
      if (_identifierLike.hasMatch(content) && !content.contains(' ')) continue;
      if (_hexColor.hasMatch(content)) continue;
      results.add(HardcodedString(
        file: path,
        line: n + 1,
        column: start,
        literal: text,
        context: trimmed,
      ));
    }
  }
  return results;
}

/// Single-line string literals on [line] (triple-quoted ones are skipped).
List<({int start, String text})> stringLiteralsOnLine(String line) {
  final matches = <({int start, String text})>[];
  var i = 0;
  while (i < line.length) {
    final ch = line[i];
    if (ch != "'" && ch != '"') {
      i++;
      continue;
    }
    if (line.startsWith('$ch$ch$ch', i)) {
      i += 3;
      while (i < line.length) {
        if (line[i] == r'\') {
          i += 2;
          continue;
        }
        if (line.startsWith('$ch$ch$ch', i)) {
          i += 3;
          break;
        }
        i++;
      }
      continue;
    }
    final start = i++;
    while (i < line.length) {
      if (line[i] == r'\') {
        i += 2;
        continue;
      }
      if (line[i] == ch) {
        matches.add((start: start, text: line.substring(start, i + 1)));
        i++;
        break;
      }
      i++;
    }
  }
  return matches;
}

/// The text of a Dart string literal's content, with escapes resolved.
String unescapeDartString(String content, {bool raw = false}) {
  if (raw) return content;
  final out = StringBuffer();
  for (var i = 0; i < content.length; i++) {
    if (content[i] == r'\' && i + 1 < content.length) {
      final next = content[++i];
      out.write(switch (next) {
        r'\' => r'\',
        "'" => "'",
        '"' => '"',
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        'b' => '\b',
        'f' => '\f',
        r'$' => r'$',
        _ => '\\$next',
      });
    } else {
      out.write(content[i]);
    }
  }
  return out.toString();
}

/// Dart interpolation (`$name`, `${name}`) as ARB placeholders (`{name}`).
/// Expressions other than a plain name are reported in `complex`.
({String converted, List<String> placeholders, List<String> complex})
    convertInterpolation(String text) {
  final out = StringBuffer();
  final placeholders = <String>[];
  final complex = <String>[];
  var i = 0;
  while (i < text.length) {
    if (text[i] == r'$' && i + 1 < text.length) {
      if (text[i + 1] == '{') {
        var depth = 1, j = i + 2;
        while (j < text.length && depth > 0) {
          if (text[j] == '{') depth++;
          if (text[j] == '}') depth--;
          j++;
        }
        final expr = text.substring(i + 2, j - 1);
        (RegExp(r'^\w+$').hasMatch(expr) ? placeholders : complex).add(expr);
        out.write('{$expr}');
        i = j;
        continue;
      }
      if (RegExp('[a-zA-Z_]').hasMatch(text[i + 1])) {
        var j = i + 1;
        while (j < text.length && RegExp(r'\w').hasMatch(text[j])) {
          j++;
        }
        final name = text.substring(i + 1, j);
        placeholders.add(name);
        out.write('{$name}');
        i = j;
        continue;
      }
    }
    out.write(text[i++]);
  }
  return (
    converted: out.toString(),
    placeholders: placeholders.toSet().toList(),
    complex: complex,
  );
}

/// A camelCase key from the first four words of [text].
String suggestKeyName(String text) {
  final words = text
      .replaceAll(RegExp(r'\{[^}]+\}'), '')
      .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .take(4)
      .toList();
  if (words.isEmpty) return 'newKey';
  final key = [
    for (var i = 0; i < words.length; i++)
      i == 0
          ? words[i].toLowerCase()
          : words[i][0].toUpperCase() + words[i].substring(1).toLowerCase(),
  ].join();
  return RegExp('^[a-z]').hasMatch(key) ? key : 'text$key';
}

/// What extracting a literal will produce.
class ExtractPlan {
  ExtractPlan({
    required this.file,
    required this.line,
    required this.column,
    required this.literal,
    required this.arbValue,
    required this.placeholders,
    required this.suggestedKey,
  });

  final String file;
  final int line;
  final int column;
  final String literal;
  final String arbValue;
  final List<String> placeholders;
  final String suggestedKey;
}

/// Read the string literal at [line] (1-based) and [column] (0-based, any
/// position inside the literal) of [file].
ExtractPlan planExtract(String file, int line, int column) {
  final lines = File(file).readAsStringSync().split('\n');
  if (line < 1 || line > lines.length) {
    throw OpException('${file.split('/').last} has no line $line.');
  }
  final text = lines[line - 1];
  ({int start, String text})? found;
  for (final m in stringLiteralsOnLine(text)) {
    if (column >= m.start && column < m.start + m.text.length) found = m;
  }
  if (found == null) {
    throw OpException('No string literal at line $line, column $column.');
  }
  final raw = found.start > 0 && text[found.start - 1] == 'r';
  final start = raw ? found.start - 1 : found.start;
  final content = found.text.substring(1, found.text.length - 1);
  final conv = convertInterpolation(unescapeDartString(content, raw: raw));
  if (conv.complex.isNotEmpty) {
    throw OpException(
      'The string interpolates expressions (${conv.complex.map((e) => '\${$e}').join(', ')}). '
      'Move them into local variables first, then extract.',
    );
  }
  return ExtractPlan(
    file: file,
    line: line,
    column: start,
    literal: raw ? 'r${found.text}' : found.text,
    arbValue: conv.converted,
    placeholders: conv.placeholders,
    suggestedKey: suggestKeyName(conv.converted),
  );
}

final _constBeforeCall = RegExp(r'const\s+([A-Z]\w*(?:\.\w+)?)\s*\(\s*$');

/// Add [plan]'s text to [module] as [key] and replace the literal with
/// `<Class>.of(context).<module>.<key>` (with arguments for placeholders).
/// A `const` directly before the enclosing constructor call is dropped, since
/// the lookup is not constant.
OpResult extractString(
  Project project,
  ExtractPlan plan, {
  required String module,
  required String key,
}) {
  final error = validateKeyName(key);
  if (error != null) throw OpException(error);
  final m = project.module(module);
  for (final f in m.arbFiles) {
    if (readArb(f.path).containsKey(key)) {
      throw OpException(
          'Key "$key" already exists in ${project.relative(f.path)}.');
    }
  }

  final result = OpResult();
  for (final f in m.arbFiles) {
    final data = readArb(f.path);
    if (f.locale == project.defaultLocale) {
      data[key] = plan.arbValue;
      if (plan.placeholders.isNotEmpty) {
        data['@$key'] = {
          'description': key,
          'placeholders': {
            for (final ph in plan.placeholders)
              ph: {'type': 'String', 'example': ph},
          },
        };
      }
    } else {
      data[key] = '';
    }
    if (writeArb(f.path, data)) result.changed.add(f.path);
  }

  final call =
      '${project.config.className}.of(context).${toCamelCase(module)}.$key'
      '${plan.placeholders.isEmpty ? '' : '(${plan.placeholders.join(', ')})'}';
  final content = File(plan.file).readAsStringSync();
  final lines = content.split('\n');
  var text = lines[plan.line - 1];
  if (!text.startsWith(plan.literal, plan.column)) {
    throw OpException('${project.relative(plan.file)} changed; scan again.');
  }
  var before = text.substring(0, plan.column);
  final constMatch = _constBeforeCall.firstMatch(before);
  if (constMatch != null) {
    before = before.substring(0, constMatch.start) +
        before
            .substring(constMatch.start)
            .replaceFirst(RegExp(r'const\s+'), '');
  }
  text = before + call + text.substring(plan.column + plan.literal.length);
  lines[plan.line - 1] = text;
  File(plan.file).writeAsStringSync(lines.join('\n'));
  result.changed.add(plan.file);
  return result;
}
