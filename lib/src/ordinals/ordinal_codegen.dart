/// Compiles the CLDR ordinal rules into Dart.
///
/// intl has no ordinal support: its own `MessageFormat` resolves
/// `selectordinal` with cardinal rules, so `2nd` would come back as `4th`.
/// The rules are therefore emitted into a generated file and called directly.
///
/// Only the groups the project's locales reference are emitted, so a project
/// with English ordinals does not carry all 28.
library;

import '../collation.dart';
import 'cldr_ordinals_data.dart';

/// Group id for a locale, falling back one subtag at a time: `zh_Hans_CN` to
/// `zh_Hans` and on to `zh`.
///
/// CLDR lists `kok_Latn` separately from `kok`, so only the exact ids in the
/// data are distinct rule sets.
String? ordinalGroupFor(String locale) {
  var candidate = locale.replaceAll('-', '_');
  final lastSubtag = RegExp(r'_[A-Za-z0-9]+$');

  while (true) {
    for (final MapEntry(key: group, value: data) in ordinalGroups.entries) {
      if (data.locales.contains(candidate)) return group;
    }
    final shorter = candidate.replaceFirst(lastSubtag, '');
    if (shorter == candidate) return null;
    candidate = shorter;
  }
}

/// The generated ordinal file for [locales], and the locales with no CLDR
/// ordinal data (which fall back to `other`).
({String content, List<String> usedLocales, List<String> unmapped})
    compileOrdinals(List<String> locales) {
  final groupIds = <String>{};
  final mapped = <String, String>{};
  final unmapped = <String>[];

  for (final locale in locales) {
    final group = ordinalGroupFor(locale);
    if (group == null) {
      if (!unmapped.contains(locale)) unmapped.add(locale);
      continue;
    }
    groupIds.add(group);
    mapped[locale] = group;
  }

  final groups = (groupIds.toList()..sort())
      .map((id) => _compileGroup(id, ordinalGroups[id]!.rules))
      .toList();

  return (
    content: _renderOrdinalFile(groups, mapped),
    usedLocales: mapped.keys.toList(),
    unmapped: unmapped,
  );
}

typedef _CompiledRule = ({String category, String test});
typedef _CompiledGroup = ({String id, List<_CompiledRule> rules});

_CompiledGroup _compileGroup(String id, List<OrdinalRule> rules) => (
      id: id,
      rules: [
        for (final rule in rules)
          (category: rule.category, test: _compileCondition(rule.condition)),
      ],
    );

/// Translate a CLDR plural-rule condition into Dart.
///
/// The grammar is tiny (`=`, `!=`, `%`, `..`, `,`, `and`, `or` over `n` and
/// `i`), so anything unexpected throws at generation time rather than
/// silently producing wrong ordinals. CLDR binds `and` tighter than `or`.
String _compileCondition(String condition) {
  return _splitKeyword(condition, 'or')
      .map(
          (part) => _splitKeyword(part, 'and').map(_compileClause).join(' && '))
      .join(' || ');
}

final _token = RegExp(r'\.\.|!=|==|[%=<>!(),]|\w+');
final _rangeSpacing = RegExp(r'\s*\.\.\s*');

/// Split a condition on a bare `and`/`or`, keeping each part tokenized.
List<String> _splitKeyword(String text, String keyword) {
  final parts = <String>[];
  final current = StringBuffer();

  void flush() {
    final part = current.toString().trim().replaceAll(_rangeSpacing, '..');
    if (part.isNotEmpty) parts.add(part);
    current.clear();
  }

  for (final match in _token.allMatches(text)) {
    final token = match.group(0)!;
    if (token == keyword) {
      flush();
      continue;
    }
    current.write('$token ');
  }
  flush();

  return parts;
}

final _clause = RegExp(r'^([ni])(?:\s*%\s*(\d+))?\s*(!?=)\s*(.+)$');
final _range = RegExp(r'^(\d+)\.\.(\d+)$');
final _number = RegExp(r'^\d+$');

/// Compile `operand [% mod] (=|!=) value_list`.
String _compileClause(String clause) {
  final match = _clause.firstMatch(clause.trim());
  if (match == null) {
    throw StateError('Unsupported CLDR ordinal condition: "$clause"');
  }

  // `n` and `i` coincide for a whole number, so both compile to the caller's
  // absolute value.
  const operand = 'v';
  final modulo = match.group(2);
  final negated = match.group(3) == '!=';
  final left = modulo != null ? '$operand % $modulo' : operand;

  final alternatives = match
      .group(4)!
      .split(',')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .map((value) => _compileValue(left, value))
      .toList();

  if (alternatives.isEmpty) {
    throw StateError('CLDR ordinal condition has no values: "$clause"');
  }

  final joined = alternatives.length == 1
      ? alternatives.single
      : '(${alternatives.join(' || ')})';
  return negated ? '!($joined)' : joined;
}

/// One comparison: an exact value, or a `low..high` range test.
String _compileValue(String left, String value) {
  final range = _range.firstMatch(value);
  if (range != null) {
    return '$left >= ${range.group(1)} && $left <= ${range.group(2)}';
  }
  if (!_number.hasMatch(value)) {
    throw StateError('Unsupported CLDR ordinal value: "$value"');
  }
  return '$left == $value';
}

String _functionName(String groupId) =>
    '_ordinal${groupId[0].toUpperCase()}${groupId.substring(1)}';

String _renderOrdinalFile(
  List<_CompiledGroup> groups,
  Map<String, String> mapped,
) {
  final functions = groups.map((group) {
    final body = [
      for (final rule in group.rules) ...[
        '  if (${rule.test}) {',
        "    return '${rule.category}';",
        '  }',
      ],
      "  return 'other';",
    ];

    final name = _functionName(group.id);

    // A rule set with no conditions has no use for the absolute value, so it
    // is not declared: an unused local is an analyzer warning.
    final header = group.rules.isNotEmpty
        ? '''/// CLDR ordinal rule set `${group.id}` ($cldrOrdinalVersion).
///
/// [n] is read as an absolute value, so a negative position ordinal reads the
/// same as its positive counterpart.
String $name(int n) {
  final v = n.abs();'''
        : '''/// CLDR ordinal rule set `${group.id}` ($cldrOrdinalVersion).
///
/// This locale defines no ordinal categories of its own, so every value
/// resolves to `other`.
String $name(int n) {''';

    return '$header\n${body.join('\n')}\n}';
  }).join('\n\n');

  final entries = (mapped.entries.toList()
        ..sort((a, b) => collate(a.key, b.key)))
      .map((e) => "  '${e.key}': ${_functionName(e.value)},")
      .join('\n');

  return '''// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated by Modular Flutter L10n Extension
// CLDR data: $cldrOrdinalVersion
$_generatedOrdinalIgnores

/// The CLDR ordinal category for [n] in [locale]: one of
/// `zero`, `one`, `two`, `few`, `many` or `other`.
///
/// intl resolves `selectordinal` with cardinal rules, so ordinals are
/// selected here instead. [locale] names come from the generated message
/// tables; an unrecognised locale yields `other`.
///
/// [n] is taken as a `num` so an `int`, `num` or `double` placeholder can
/// all be passed; ordinal categories are defined over integers, so a fractional
/// value is truncated rather than rejected.
String modularOrdinalCategory(String locale, num n) {
  return _ordinalRules[locale]?.call(n.truncate()) ?? 'other';
}

/// Pick the branch [category] names from a rendered case list.
///
/// Public, unlike the rule sets: this is called from the message tables and the
/// module files, which are separate libraries. A Dart underscore prefix is
/// library-private, so a private helper would not resolve at the call site.
String modularOrdinalBranch(String category, Map<String, String> cases) {
  return cases[category] ?? cases['other']!;
}

typedef _OrdinalRule = String Function(int n);

final Map<String, _OrdinalRule> _ordinalRules = <String, _OrdinalRule>{
$entries
};

$functions
''';
}

const _generatedOrdinalIgnores =
    '// ignore_for_file: non_constant_identifier_names, unnecessary_string_escapes,\n'
    '// ignore_for_file: unnecessary_brace_in_string_interps, unused_import, prefer_single_quotes';
