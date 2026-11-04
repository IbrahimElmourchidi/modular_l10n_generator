/// JSON output identical to JavaScript's `JSON.stringify(value, null, 2)`, so
/// combined ARB files match the VS Code extension's byte for byte.
///
/// Differences from `dart:convert` that this covers: integral doubles print
/// as `2`, not `2.0`, and lone surrogates are escaped instead of replaced.
library;

import 'arb_parser.dart' show jsString;

/// Encode [value] (maps, lists, strings, numbers, booleans, null) with
/// two-space indentation and no trailing newline.
String encodeJsonLikeJs(Object? value) {
  final out = StringBuffer();
  _write(out, value, '');
  return out.toString();
}

void _write(StringBuffer out, Object? value, String indent) {
  switch (value) {
    case null:
      out.write('null');
    case bool():
      out.write(value);
    case num():
      out.write(value.isFinite ? jsString(value) : 'null');
    case String():
      _writeString(out, value);
    case Map<Object?, Object?>():
      if (value.isEmpty) {
        out.write('{}');
        return;
      }
      final inner = '$indent  ';
      out.write('{\n');
      var first = true;
      for (final MapEntry(:key, :value) in value.entries) {
        if (!first) out.write(',\n');
        first = false;
        out.write(inner);
        _writeString(out, '$key');
        out.write(': ');
        _write(out, value, inner);
      }
      out.write('\n$indent}');
    case List<Object?>():
      if (value.isEmpty) {
        out.write('[]');
        return;
      }
      final inner = '$indent  ';
      out.write('[\n');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) out.write(',\n');
        out.write(inner);
        _write(out, value[i], inner);
      }
      out.write('\n$indent]');
    default:
      _writeString(out, value.toString());
  }
}

void _writeString(StringBuffer out, String s) {
  out.write('"');
  for (var i = 0; i < s.length; i++) {
    final unit = s.codeUnitAt(i);
    switch (unit) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x08:
        out.write(r'\b');
      case 0x0c:
        out.write(r'\f');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        if (unit < 0x20) {
          out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
        } else if (unit >= 0xd800 && unit <= 0xdbff) {
          final next = i + 1 < s.length ? s.codeUnitAt(i + 1) : 0;
          if (next >= 0xdc00 && next <= 0xdfff) {
            out.writeCharCode(unit);
            out.writeCharCode(next);
            i++;
          } else {
            out.write('\\u${unit.toRadixString(16)}');
          }
        } else if (unit >= 0xdc00 && unit <= 0xdfff) {
          out.write('\\u${unit.toRadixString(16)}');
        } else {
          out.writeCharCode(unit);
        }
    }
  }
  out.write('"');
}
