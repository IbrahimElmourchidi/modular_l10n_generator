/// An ICU MessageFormat parser for ARB messages.
///
/// The grammar is parsed once into a tree, and everything downstream
/// (rendering, argument collection, validation) reads that tree instead of
/// re-scanning the string. Regexes cannot see block structure: they let a
/// `select` nested in a plural through as literal text, and `one{` matched
/// inside the word "Someone{".
///
/// Design notes:
///
/// - **Never throws.** Malformed input yields an [IcuInvalid] node plus an
///   error, and parsing continues with the rest of the message. A broken ARB
///   file must still produce a usable generator run with a diagnostic.
/// - **Every node carries `start`/`end` offsets** (UTF-16 code units) into the
///   source string, so a diagnostic can point at the exact construct.
/// - **Apostrophes follow ICU, not Dart.** `''` is a literal apostrophe and a
///   lone `'` quotes the next special character. See [_Parser._readText].
library;

/// What a name is *for*, which decides the generated Dart parameter type.
enum ArgRole {
  /// `{name}`: interpolated as-is.
  plain,

  /// `{gender, select, …}`: a keyword, so a `String`.
  selectOperand,

  /// `{count, plural, …}`: the value a CLDR plural category is chosen from.
  pluralOperand,

  /// `{n, selectordinal, …}`: as above, but ordinal rules.
  ordinalOperand,
}

/// A name a message needs, tagged with the role that decides its type.
class IcuArg {
  const IcuArg(this.name, this.role, [this.conflict]);

  final String name;

  /// The strictest role the name was reached through.
  final ArgRole role;

  /// The other *operand* roles the name was also reached through, set only
  /// when there is more than one. `plain` never counts as a conflict.
  final List<ArgRole>? conflict;
}

/// A node of the parse tree.
sealed class IcuNode {
  const IcuNode(this.start, this.end);

  /// Offset of the construct's first character in the source string.
  final int start;

  /// Offset one past the construct's last character.
  final int end;
}

/// Literal text, already unescaped (`''` collapsed, quoted runs unwrapped).
final class IcuText extends IcuNode {
  const IcuText(
    this.value,
    super.start,
    super.end, {
    this.quotedSyntax = false,
    this.sourceHashOffsets = const [],
  });

  final String value;

  /// Whether this node holds a syntax character the author quoted on purpose.
  final bool quotedSyntax;

  /// Source offset of each literal `#` in [value], in order.
  final List<int> sourceHashOffsets;
}

/// `#` inside a plural or selectordinal body, standing for the
/// (offset-shifted) plural value. Outside such a block `#` is ordinary text.
final class IcuHash extends IcuNode {
  const IcuHash(super.start, super.end);
}

/// A plain `{name}` placeholder.
final class IcuArgRef extends IcuNode {
  const IcuArgRef(this.name, super.start, super.end);

  final String name;
}

/// `{name, select, …}`.
final class IcuSelect extends IcuNode {
  const IcuSelect(this.name, this.cases, super.start, super.end);

  final String name;

  /// Case key to body, in source order.
  final Map<String, List<IcuNode>> cases;
}

/// `{name, plural, …}` or `{name, selectordinal, …}`.
final class IcuPlural extends IcuNode {
  const IcuPlural({
    required this.name,
    required this.ordinal,
    required this.offset,
    required this.cases,
    required this.exactSelectors,
    required int start,
    required int end,
  }) : super(start, end);

  final String name;
  final bool ordinal;

  /// `offset:n`: subtracted before category selection and before `#`
  /// substitution. Exact `=N` selectors still match the *raw* value.
  final int offset;

  /// Case key to body. Keys are `zero`…`other` or exact `=N`.
  final Map<String, List<IcuNode>> cases;

  /// Exact selectors (`=0`, `=5`, …) in source order.
  final List<String> exactSelectors;
}

/// Malformed or unsupported input, kept verbatim.
final class IcuInvalid extends IcuNode {
  const IcuInvalid(this.raw, this.error, super.start, super.end);

  final String raw;
  final String error;
}

/// A non-fatal parse problem.
class IcuParseError {
  const IcuParseError(this.message, this.start, this.end);

  final String message;
  final int start;
  final int end;

  @override
  String toString() => message;
}

/// The result of [parseIcu].
class IcuParseResult {
  const IcuParseResult(this.nodes, this.errors);

  final List<IcuNode> nodes;
  final List<IcuParseError> errors;
}

const _icuTypes = {'select', 'plural', 'selectordinal'};
final _category = RegExp(r'^(?:zero|one|two|few|many|other)$');
final _identifier = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');
final _digits = RegExp(r'\d+');
final _offset = RegExp(r'offset\s*:\s*(\d+)');
final _whitespace = RegExp(r'\s');
final _swallowedPlaceholder =
    RegExp(r'\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:,[^}]*)?\}');

/// Parse an ICU message.
IcuParseResult parseIcu(String text) {
  final errors = <IcuParseError>[];
  final nodes = _Parser(text, errors).parseNodes(false);
  return IcuParseResult(nodes, errors);
}

/// Every argument a message needs, in first-appearance order, each tagged
/// with the strictest role it was reached through.
///
/// Recurses into case bodies, so a `select` nested inside a plural becomes a
/// real parameter.
List<IcuArg> collectArgs(List<IcuNode> nodes) {
  final found = <String, List<ArgRole>>{};

  void record(String name, ArgRole role) {
    final roles = found[name];
    if (roles == null) {
      found[name] = [role];
    } else if (!roles.contains(role)) {
      roles.add(role);
    }
  }

  void walk(List<IcuNode> list) {
    for (final node in list) {
      switch (node) {
        case IcuArgRef(:final name):
          record(name, ArgRole.plain);
        case IcuSelect(:final name, :final cases):
          record(name, ArgRole.selectOperand);
          cases.values.forEach(walk);
        case IcuPlural(:final name, :final ordinal, :final cases):
          record(
              name, ordinal ? ArgRole.ordinalOperand : ArgRole.pluralOperand);
          cases.values.forEach(walk);
        case IcuText() || IcuHash() || IcuInvalid():
          break;
      }
    }
  }

  walk(nodes);

  return [
    for (final MapEntry(key: name, value: roles) in found.entries)
      () {
        // Ranks are unique per role, so sort stability does not matter.
        final ranked = [...roles]..sort((a, b) => b.index - a.index);
        final operandRoles = ranked.where((r) => r != ArgRole.plain).toList();
        return operandRoles.length > 1
            ? IcuArg(name, ranked.first, operandRoles.sublist(1))
            : IcuArg(name, ranked.first);
      }(),
  ];
}

/// A short, stable description of a message's ICU *control* structure: its
/// `select` / `plural` / `selectordinal` blocks and the arguments they select
/// on, in source order. Literal text and plain `{name}` positions are absent.
String describeIcuControls(List<IcuNode> nodes) {
  final parts = <String>[];

  void walk(List<IcuNode> list) {
    for (final node in list) {
      switch (node) {
        case IcuSelect(:final name, :final cases):
          parts.add('select($name)');
          cases.values.forEach(walk);
        case IcuPlural(
            :final name,
            :final ordinal,
            :final offset,
            :final cases
          ):
          final kind = ordinal ? 'ordinal' : 'plural';
          parts.add('$kind($name${offset != 0 ? ' offset:$offset' : ''})');
          cases.values.forEach(walk);
        case IcuText() || IcuHash() || IcuArgRef() || IcuInvalid():
          break;
      }
    }
  }

  walk(nodes);
  return parts.join('+');
}

/// Whether [nodes] contain a node matching [predicate], at any depth.
bool containsIcuNode(List<IcuNode> nodes, bool Function(IcuNode) predicate) {
  for (final node in nodes) {
    if (predicate(node)) return true;
    final cases = switch (node) {
      IcuSelect(:final cases) => cases,
      IcuPlural(:final cases) => cases,
      _ => null,
    };
    if (cases != null) {
      for (final body in cases.values) {
        if (containsIcuNode(body, predicate)) return true;
      }
    }
  }
  return false;
}

class _Parser {
  _Parser(this._src, this._errors);

  final String _src;
  final List<IcuParseError> _errors;
  int _pos = 0;

  /// The code unit at [i] as a one-character string, or `null` past the end.
  String? _at(int i) => i < _src.length ? _src[i] : null;

  /// Parse until the end of input, or until the `}` that closes an enclosing
  /// block when [stopAtClose] is set.
  ///
  /// [inPlural]: when true, a bare `#` is a plural-value reference.
  List<IcuNode> parseNodes(bool inPlural, [bool stopAtClose = false]) {
    final nodes = <IcuNode>[];

    while (_pos < _src.length) {
      final ch = _src[_pos];

      if (ch == '}') {
        if (stopAtClose) break;
        // A stray `}` with no owner: record it and keep the character.
        _errors.add(IcuParseError("Unmatched '}'", _pos, _pos + 1));
        nodes.add(IcuText('}', _pos, _pos + 1));
        _pos++;
        continue;
      }

      if (ch == '{') {
        nodes.add(_parseArgument(inPlural));
        continue;
      }

      if (ch == '#') {
        nodes.add(_readHash(inPlural));
        continue;
      }

      final start = _pos;
      final text = _readText(inPlural);
      if (text.value.isNotEmpty) nodes.add(text);
      // Defensive: never loop forever on an unconsumable character.
      if (_pos == start) _pos++;
    }

    return nodes;
  }

  IcuNode _parseArgument(bool inPlural) {
    final start = _pos;

    _pos++; // the '{'
    _skipWhitespace();

    final name = _readIdentifier();
    if (name == null) {
      return _invalid(start, _pos, "Expected a placeholder name after '{'");
    }

    _skipWhitespace();

    // `{name}`: a plain placeholder. Anything else is a block.
    if (_at(_pos) == '}') {
      final end = _pos + 1;
      _pos = end;
      return IcuArgRef(name, start, end);
    }

    if (_at(_pos) != ',') {
      return _invalid(
          start, _pos, "Expected ',' or '}' in placeholder \"$name\"");
    }

    _pos++;
    _skipWhitespace();
    final typeStart = _pos;
    final type = _readIdentifier();
    if (type == null) {
      return _invalid(start, _pos, "Expected a type after ',' in \"$name\"");
    }

    if (!_icuTypes.contains(type)) {
      // `date`, `number`, `time` are valid ICU but not supported here.
      // Consume to the matching '}' so the rest of the message still parses.
      final end = _skipToBlockEnd();
      _errors.add(IcuParseError(
        'Unsupported ICU argument type "$type" in "$name"; '
        'it will be rendered as literal text',
        typeStart,
        end,
      ));
      return IcuInvalid(
        _src.substring(start, end),
        'unsupported type "$type"',
        start,
        end,
      );
    }

    _skipWhitespace();
    if (_at(_pos) != ',') {
      return _invalid(start, _pos, "Expected ',' after \"$type\" in \"$name\"");
    }
    _pos++;

    if (type == 'select') {
      // A select has no operand of its own, but `#` resolves against the
      // nearest *enclosing* plural, so that binding is inherited.
      final cases = <String, List<IcuNode>>{};
      final end = _parseCases(cases, 'select', start, name, null, inPlural);
      return IcuSelect(name, cases, start, end);
    }
    return _parsePluralBody(name, type == 'selectordinal', start);
  }

  IcuNode _parsePluralBody(String name, bool ordinal, int start) {
    final cases = <String, List<IcuNode>>{};
    final exactSelectors = <String>[];
    var offset = 0;

    // `offset:n` may precede the first selector.
    _skipWhitespace();
    final offsetMatch = _offset.matchAsPrefix(_src, _pos);
    if (offsetMatch != null) {
      offset = int.tryParse(offsetMatch.group(1)!) ?? 0;
      _pos = offsetMatch.end;
    }

    final end = _parseCases(cases, 'plural', start, name, exactSelectors, true);
    return IcuPlural(
      name: name,
      ordinal: ordinal,
      offset: offset,
      cases: cases,
      exactSelectors: exactSelectors,
      start: start,
      end: end,
    );
  }

  /// Shared case-list parser for `select` and `plural`/`selectordinal`.
  int _parseCases(
    Map<String, List<IcuNode>> cases,
    String type,
    int blockStart,
    String name,
    List<String>? exactSelectors,
    bool inPlural,
  ) {
    while (true) {
      _skipWhitespace();
      final ch = _at(_pos);

      if (ch == null) {
        _errors.add(IcuParseError(
          'Unclosed "$type" block for "$name"',
          blockStart,
          _src.length,
        ));
        return _src.length;
      }

      if (ch == '}') {
        // A missing `other` is not reported here: the renderer synthesizes a
        // fallback, which makes it a translation problem, not a parse one.
        final end = _pos + 1;
        _pos = end;
        return end;
      }

      final selectorStart = _pos;

      // `=5`: an exact selector, distinct from a category name.
      if (ch == '=') {
        _pos++;
        final digits = _digits.matchAsPrefix(_src, _pos);
        if (digits == null) {
          _errors.add(IcuParseError(
            "Expected a number after '=' in \"$name\"",
            selectorStart,
            _pos,
          ));
          _skipToBlockEnd();
          return _pos;
        }
        _pos = digits.end;
        final selector = '=${digits.group(0)}';
        if (cases.containsKey(selector)) {
          _errors.add(IcuParseError(
            'Duplicate case "$selector" in "$name"',
            selectorStart,
            _pos,
          ));
        }
        exactSelectors?.add(selector);
        if (_readCaseBody(cases, selector, name, inPlural) == null) return _pos;
        continue;
      }

      final selector = _readIdentifier();
      if (selector == null) {
        _errors.add(IcuParseError(
          'Expected a case name in "$name"',
          selectorStart,
          _pos,
        ));
        _skipToBlockEnd();
        return _pos;
      }

      // A select keyword is arbitrary. Only a plural/ordinal selector is
      // constrained, to a CLDR category or an exact `=N`.
      if (type == 'plural' && !_category.hasMatch(selector)) {
        _errors.add(IcuParseError(
          '"$selector" is not a plural category for "$name" '
          '(expected zero, one, two, few, many, other, or =N)',
          selectorStart,
          _pos,
        ));
      }

      if (cases.containsKey(selector)) {
        _errors.add(IcuParseError(
          'Duplicate case "$selector" in "$name"',
          selectorStart,
          _pos,
        ));
      }

      if (_readCaseBody(cases, selector, name, inPlural) == null) return _pos;
    }
  }

  /// Read one `caseName { body }` and record it. Returns the offset after the
  /// body, or `null` when parsing had to bail out.
  int? _readCaseBody(
    Map<String, List<IcuNode>> cases,
    String selector,
    String name,
    bool inPlural,
  ) {
    _skipWhitespace();

    if (_at(_pos) != '{') {
      _errors.add(IcuParseError(
        "Expected '{' after case \"$selector\" in \"$name\"",
        _pos,
        _pos,
      ));
      _skipToBlockEnd();
      return null;
    }
    _pos++;

    final bodyStart = _pos;
    final body = parseNodes(inPlural, true);

    if (_at(_pos) != '}') {
      _errors.add(IcuParseError(
        'Unclosed case "$selector" in "$name"',
        bodyStart,
        _src.length,
      ));
      cases[selector] = body;
      return _src.length;
    }

    cases[selector] = body;
    final end = _pos + 1;
    _pos = end;
    return end;
  }

  /// Read literal text up to the next `{`, `}` or, inside a plural, `#`.
  ///
  /// Handles ICU quoting: `''` is one literal apostrophe, and a `'` before a
  /// syntax character opens a quoted run that ends at the next lone `'`.
  IcuText _readText(bool inPlural) {
    final start = _pos;
    final out = StringBuffer();
    var quotedSyntax = false;
    final sourceHashOffsets = <int>[];

    while (_pos < _src.length) {
      final ch = _src[_pos];

      if (ch == '{' || ch == '}' || (ch == '#' && inPlural)) break;

      if (ch == "'") {
        final next = _at(_pos + 1);

        // '' -> a literal apostrophe.
        if (next == "'") {
          out.write("'");
          _pos += 2;
          continue;
        }

        // A quote only opens a literal run before a syntax character. `#` is
        // one only inside a plural. `|` is deliberately not one.
        final quotesHash = next == '#' && inPlural;
        if (next == '{' || next == '}' || quotesHash) {
          final runStart = _pos + 1;
          var sawSyntax = quotesHash;
          var closed = false;
          _pos++;
          while (_pos < _src.length) {
            final inner = _src[_pos];

            if (inner == '{' || inner == '}' || inner == '#') sawSyntax = true;

            if (inner == "'") {
              // '' inside a run is a literal apostrophe.
              if (_at(_pos + 1) == "'") {
                out.write("'");
                _pos += 2;
                continue;
              }
              _pos++;
              closed = true;
              break;
            }
            out.write(inner);
            _pos++;
          }
          if (sawSyntax) quotedSyntax = true;
          _reportQuotedRun(runStart, _pos, closed);
          continue;
        }

        // A lone apostrophe is just an apostrophe.
        out.write("'");
        if (next == '#') quotedSyntax = true;
        _pos++;
        continue;
      }

      // Only reached outside a plural; inside one `#` breaks the loop above.
      if (ch == '#') sourceHashOffsets.add(_pos);

      out.write(ch);
      _pos++;
    }

    return IcuText(
      out.toString(),
      start,
      _pos,
      quotedSyntax: quotedSyntax,
      sourceHashOffsets: sourceHashOffsets,
    );
  }

  /// Report the two ways an apostrophe-quoted run goes wrong: it swallowed a
  /// placeholder (`l'{place} aujourd'hui`), or it never closes.
  void _reportQuotedRun(int runStart, int runEnd, bool closed) {
    if (!closed) {
      _errors.add(IcuParseError(
        'This apostrophe opens a quoted run that never closes, so everything '
        'after it is literal text. Write "\'\'" for a literal apostrophe.',
        runStart - 1,
        runEnd,
      ));
      return;
    }

    final inner = _src.substring(runStart, runEnd - 1);
    final swallowed = _swallowedPlaceholder.firstMatch(inner);
    if (swallowed != null) {
      final name = swallowed.group(1);
      _errors.add(IcuParseError(
        'This apostrophe quotes "{" as literal text, so "{$name}" is '
        'not interpolated and the message has no such parameter. Write "\'\'" '
        "for a literal apostrophe, or quote the whole placeholder as '{$name}'.",
        runStart - 1,
        runEnd,
      ));
    }
  }

  /// A `#` node inside a plural, literal text outside one.
  IcuNode _readHash(bool inPlural) {
    final start = _pos;
    _pos++;
    return inPlural ? IcuHash(start, _pos) : IcuText('#', start, _pos);
  }

  void _skipWhitespace() {
    while (_pos < _src.length && _whitespace.hasMatch(_src[_pos])) {
      _pos++;
    }
  }

  String? _readIdentifier() {
    final match = _identifier.matchAsPrefix(_src, _pos);
    if (match == null) return null;
    _pos = match.end;
    return match.group(0);
  }

  /// Consume to just past the `}` that closes the current block.
  int _skipToBlockEnd() {
    var depth = 1;
    var i = _pos;
    while (i < _src.length && depth > 0) {
      if (_src[i] == '{') {
        depth++;
      } else if (_src[i] == '}') {
        depth--;
      }
      if (depth == 0) break;
      i++;
    }
    _pos = i + 1 < _src.length ? i + 1 : _src.length;
    return _pos;
  }

  IcuInvalid _invalid(int start, int end, String error) {
    final safeEnd = end > start ? end : start;
    _errors.add(IcuParseError(error, start, safeEnd));
    return IcuInvalid(_src.substring(start, safeEnd), error, start, safeEnd);
  }
}
