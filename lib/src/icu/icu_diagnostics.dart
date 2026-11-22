/// ICU message checks, ported from the VS Code extension's
/// `icu_diagnostics.ts`. The generator repairs what it can, so a broken
/// message can still produce buildable but wrong Dart; these checks report
/// it to the translator instead.
library;

import 'icu_parser.dart';
import 'icu_types.dart';

enum IcuSeverity { error, warning, hint }

class IcuDiagnostic {
  const IcuDiagnostic({
    required this.key,
    required this.start,
    required this.end,
    required this.severity,
    required this.message,
    required this.code,
  });

  final String key;

  /// Offsets into the message value.
  final int start;
  final int end;
  final IcuSeverity severity;
  final String message;
  final String code;
}

/// Dart's reserved words and the built-in identifiers that cannot be a
/// parameter or member name.
const dartReserved = {
  'abstract', 'as', 'assert', 'async', 'augment', 'await', 'base', 'break', //
  'case', 'catch', 'class', 'const', 'continue', 'covariant', 'default',
  'deferred', 'do', 'dynamic', 'else', 'enum', 'export', 'extends',
  'extension', 'external', 'factory', 'false', 'final', 'finally', 'for',
  'Function', 'get', 'hide', 'if', 'implements', 'import', 'in', 'interface',
  'is', 'late', 'library', 'mixin', 'new', 'null', 'on', 'operator', 'part',
  'required', 'rethrow', 'return', 'sealed', 'set', 'show', 'static', 'super',
  'switch', 'sync', 'this', 'throw', 'true', 'try', 'type', 'typedef', 'var',
  'void', 'when', 'while', 'with', 'yield',
};

final _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

/// Check one ARB message.
///
/// [template] is the template-locale value of the same key, for the
/// control-difference hint; [canonicalArgs] is the template's argument list,
/// for the cross-locale argument check (skipped when `null`).
List<IcuDiagnostic> diagnoseIcuMessage(
  String key,
  String text, {
  String? template,
  List<CanonicalArg>? canonicalArgs,
}) {
  final out = <IcuDiagnostic>[];
  final parsed = parseIcu(text);
  final nodes = parsed.nodes;

  if (key.isNotEmpty &&
      (!_identifier.hasMatch(key) || dartReserved.contains(key))) {
    out.add(IcuDiagnostic(
      key: key,
      start: 0,
      end: key.length,
      severity: IcuSeverity.error,
      message:
          '"$key" cannot be used as a Dart method name. Rename the message key.',
      code: 'icu-dart-keyword',
    ));
  }

  for (final arg in collectArgs(nodes)) {
    if (_identifier.hasMatch(arg.name) && !dartReserved.contains(arg.name)) {
      continue;
    }
    final at = text.indexOf('{${arg.name}}').clamp(0, text.length);
    out.add(IcuDiagnostic(
      key: key,
      start: at,
      end: at + arg.name.length + 2,
      severity: IcuSeverity.error,
      message:
          '"{${arg.name}}" cannot be used as a Dart parameter name. Rename '
          'the placeholder in the message and in @$key.placeholders.',
      code: 'icu-dart-keyword',
    ));
  }

  for (final error in parsed.errors) {
    out.add(IcuDiagnostic(
      key: key,
      start: error.start,
      end: error.end,
      severity: IcuSeverity.error,
      message: error.message,
      code: 'icu-syntax',
    ));
  }

  for (var i = 0; i < nodes.length; i++) {
    _blockDiagnostics(key, nodes[i], i, nodes, parsed.errors, out);
  }

  final incompatible = canonicalArgs == null
      ? null
      : firstIncompatibleArg(canonicalArgs, collectArgs(nodes));
  if (incompatible != null) {
    out.add(IcuDiagnostic(
      key: key,
      start: 0,
      end: text.length,
      severity: IcuSeverity.error,
      message: 'This translation cannot be generated: ${incompatible.reason}. '
          'The template translation will be used for this locale instead.',
      code: 'icu-argument-mismatch',
    ));
  }

  if (incompatible == null &&
      text.trim().isNotEmpty &&
      template != null &&
      template != text) {
    final controls = describeIcuControls(nodes);
    final templateControls = describeIcuControls(parseIcu(template).nodes);
    if (controls != templateControls &&
        (controls.isEmpty || templateControls.isEmpty)) {
      out.add(IcuDiagnostic(
        key: key,
        start: 0,
        end: text.length,
        severity: IcuSeverity.hint,
        message: 'This locale ${controls.isNotEmpty ? 'adds' : 'drops'} ICU '
            'blocks the template does not have (template: '
            '${templateControls.isEmpty ? 'none' : templateControls}, here: '
            '${controls.isEmpty ? 'none' : controls}). Both render, but check '
            'the wording agrees.',
        code: 'icu-control-difference',
      ));
    }
  }
  return out;
}

void _blockDiagnostics(
  String key,
  IcuNode node,
  int index,
  List<IcuNode> siblings,
  List<IcuParseError> parseErrors,
  List<IcuDiagnostic> out,
) {
  bool brokenByParseError() =>
      parseErrors.any((e) => e.start >= node.start && e.start < node.end);

  void children(Map<String, List<IcuNode>> cases) {
    for (final body in cases.values) {
      for (var i = 0; i < body.length; i++) {
        _blockDiagnostics(key, body[i], i, body, parseErrors, out);
      }
    }
  }

  switch (node) {
    case IcuPlural():
      final kind = node.ordinal ? 'selectordinal' : 'plural';
      if (!node.cases.containsKey('other') && !brokenByParseError()) {
        out.add(IcuDiagnostic(
          key: key,
          start: node.start,
          end: node.end,
          severity: IcuSeverity.error,
          message: '"$kind" block for "${node.name}" has no "other" case. '
              'Add one — it is required.',
          code: 'icu-missing-other',
        ));
      }
      if (node.ordinal && node.exactSelectors.contains('=0')) {
        out.add(IcuDiagnostic(
          key: key,
          start: node.start,
          end: node.end,
          severity: IcuSeverity.hint,
          message: 'An exact "=0" selector in an ordinal block wins for 0 '
              'itself, before CLDR rules are consulted. Check the ordinals '
              'read correctly for this locale.',
          code: 'icu-ordinal-exact',
        ));
      }
      children(node.cases);
    case IcuSelect():
      if (!node.cases.containsKey('other') && !brokenByParseError()) {
        out.add(IcuDiagnostic(
          key: key,
          start: node.start,
          end: node.end,
          severity: IcuSeverity.error,
          message: '"select" block for "${node.name}" has no "other" case. '
              'Add one — it is required.',
          code: 'icu-missing-other',
        ));
      }
      children(node.cases);
    case IcuText():
      if (!node.value.contains('#') || node.quotedSyntax) return;
      final next = index + 1 < siblings.length ? siblings[index + 1] : null;
      if (next is IcuArgRef && node.end == next.start) return;
      final hash = node.sourceHashOffsets.isNotEmpty
          ? node.sourceHashOffsets.first
          : node.start + node.value.indexOf('#');
      out.add(IcuDiagnostic(
        key: key,
        start: hash,
        end: hash + 1,
        severity: IcuSeverity.hint,
        message: 'This "#" is literal text because it is not inside a plural '
            'or ordinal block. Use "{count, plural, …}" if it should become '
            'the number.',
        code: 'icu-hash-literal',
      ));
    case IcuInvalid() || IcuHash() || IcuArgRef():
      return;
  }
}
