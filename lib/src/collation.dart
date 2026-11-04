/// String ordering that matches ICU's root collation for ASCII text, which is
/// what `String.prototype.localeCompare(b, 'en')` does in the VS Code
/// extension.
///
/// It matters because ARB files are discovered in this order, and that order
/// decides the module order in the generated files. Plain code-unit order
/// puts `auth/` before `auth_extra/` where ICU puts `_` first, so the two
/// tools would emit the same project with getters in a different order.
///
/// Comparison is ICU-style: first by primary weight (punctuation in CLDR
/// order, then digits, then letters case-insensitively), then lowercase before
/// uppercase, then code units. Non-ASCII characters sort after ASCII by code
/// unit, which is an approximation of ICU but a stable one.
library;

const _asciiOrder = ' _-,;:!?.\'"()[]{}@*/\\&#%`^+<=>|~\$0123456789'
    'abcdefghijklmnopqrstuvwxyz';

final List<int> _primary = () {
  final table = List<int>.filled(128, -1);
  for (var i = 0; i < _asciiOrder.length; i++) {
    final unit = _asciiOrder.codeUnitAt(i);
    table[unit] = i;
    if (unit >= 0x61 && unit <= 0x7a) table[unit - 0x20] = i;
  }
  return table;
}();

int _primaryWeight(int unit) {
  if (unit < 128) {
    final weight = _primary[unit];
    // Control characters: before everything printable.
    return weight >= 0 ? weight + 1 : 0;
  }
  return _asciiOrder.length + 1 + unit;
}

/// Compare [a] and [b] the way ICU's root collation does for ASCII text.
int collate(String a, String b) {
  final length = a.length < b.length ? a.length : b.length;

  for (var i = 0; i < length; i++) {
    final diff =
        _primaryWeight(a.codeUnitAt(i)) - _primaryWeight(b.codeUnitAt(i));
    if (diff != 0) return diff;
  }
  if (a.length != b.length) return a.length - b.length;

  // Same letters, different case: lowercase first.
  for (var i = 0; i < length; i++) {
    final x = a.codeUnitAt(i);
    final y = b.codeUnitAt(i);
    if (x == y) continue;
    final xUpper = x >= 0x41 && x <= 0x5a;
    final yUpper = y >= 0x41 && y <= 0x5a;
    if (xUpper != yUpper) return xUpper ? 1 : -1;
  }

  return a.compareTo(b);
}
