/// The Dart type vocabulary the generator emits, and how an ICU role
/// constrains it.
///
/// Every `plural` or `selectordinal` renders as a call into `package:intl`
/// whose parameter type is fixed by that library:
///
///     static String plural(num howMany, {String? zero, String? one, …})
///     static String select(Object choice, Map<Object, String> cases)
///
/// `plural` is strict (`num`, not `Object`), so a name the canonical
/// signature types as anything else is a compile error the moment a locale
/// uses it as an operand. `select` takes an `Object`, so it constrains
/// nothing. A plain `{name}` interpolation calls `toString`.
library;

import 'icu_parser.dart';

/// Declared placeholder types that satisfy `Intl.plural`'s `num howMany`.
const numericDartTypes = {'int', 'num', 'double'};

/// A named placeholder and the Dart type the generated method gives it.
class CanonicalArg {
  const CanonicalArg(this.name, this.dartType);

  final String name;
  final String dartType;
}

/// The Dart type a placeholder's parameter should have.
///
/// `@key.placeholders` may only *narrow* the type, never contradict it: a
/// name that plays a plural operand has to be numeric.
String resolvePlaceholderDartType(
  String? declaredType,
  String name,
  List<IcuArg> args,
) {
  final role = _roleOf(args, name);
  switch (role) {
    case ArgRole.pluralOperand:
    case ArgRole.ordinalOperand:
      if (declaredType != null && numericDartTypes.contains(declaredType)) {
        return declaredType;
      }
      return role == ArgRole.ordinalOperand ? 'int' : 'num';
    case ArgRole.selectOperand:
      return declaredType ?? 'String';
    case ArgRole.plain:
    case null:
      return declaredType ?? 'Object';
  }
}

ArgRole? _roleOf(List<IcuArg> args, String name) {
  for (final arg in args) {
    if (arg.name == name) return arg.role;
  }
  return null;
}

/// The canonical argument list for a message: every name the message uses,
/// paired with the Dart type its parameter should have.
///
/// [declaredTypeOf] returns the `type` declared in `@key.placeholders`, if
/// any.
List<CanonicalArg> buildCanonicalArgs(
  List<IcuArg> args,
  String? Function(String name) declaredTypeOf,
) {
  return [
    for (final arg in args)
      CanonicalArg(
        arg.name,
        resolvePlaceholderDartType(declaredTypeOf(arg.name), arg.name, args),
      ),
  ];
}

/// Why a type cannot serve a role, for a diagnostic. `null` means it can.
typedef RoleIncompatibility = ({String role, String needs});

const _roleLabel = {
  ArgRole.pluralOperand: 'a plural operand',
  ArgRole.ordinalOperand: 'an ordinal operand',
  ArgRole.selectOperand: 'a select operand',
  ArgRole.plain: 'plain text',
};

/// Whether a parameter typed [dartType] can be rendered in [role] and still
/// compile. Returns `null` when it can.
RoleIncompatibility? checkRoleCompatibility(String dartType, ArgRole role) {
  switch (role) {
    case ArgRole.pluralOperand:
    case ArgRole.ordinalOperand:
      return numericDartTypes.contains(dartType)
          ? null
          : (role: _roleLabel[role]!, needs: 'num');
    case ArgRole.selectOperand:
    case ArgRole.plain:
      return null;
  }
}

/// The first argument a translation cannot be rendered with, or `null` when
/// it can.
///
/// Two things make a translation unrenderable, and both are compile errors:
/// it names an argument the canonical signature does not have, or it uses a
/// name in a role that parameter's type cannot serve. Differences in wording,
/// word order or block count are *not* checked; those are ordinary results of
/// translating.
({String name, String reason})? firstIncompatibleArg(
  List<CanonicalArg> canonicalArgs,
  List<IcuArg> usedArgs,
) {
  final canonical = {for (final a in canonicalArgs) a.name: a};

  for (final used in usedArgs) {
    final declared = canonical[used.name];
    if (declared == null) {
      return (
        name: used.name,
        reason: '"${used.name}" is not an argument of the template translation',
      );
    }

    final problem = checkRoleCompatibility(declared.dartType, used.role);
    if (problem != null) {
      return (
        name: used.name,
        reason: '"${used.name}" is `${declared.dartType}` but the translation '
            'uses it as ${problem.role}, which needs a `${problem.needs}`',
      );
    }
  }

  return null;
}
