/// Reading and writing ARB files the way the VS Code extension does, plus the
/// naming rules every command validates against.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../json_writer.dart';
import '../module_scanner.dart' show readJsonFile;

/// A module name: snake_case, as used in `@@context`.
final moduleNamePattern = RegExp(r'^[a-z][a-z0-9_]*$');

/// A translation key: camelCase, starting with a lowercase letter.
final keyNamePattern = RegExp(r'^[a-z][a-zA-Z0-9]*$');

/// A generated class name: PascalCase.
final classNamePattern = RegExp(r'^[A-Z][a-zA-Z0-9]*$');

/// `null` when [name] is a valid module name, otherwise why it is not.
String? validateModuleName(String name) => moduleNamePattern.hasMatch(name)
    ? null
    : 'Module names are snake_case: a lowercase letter, then lowercase '
        'letters, digits or underscores (for example auth, user_profile).';

/// `null` when [key] is a valid translation key, otherwise why it is not.
String? validateKeyName(String key) => keyNamePattern.hasMatch(key)
    ? null
    : 'Keys are camelCase: a lowercase letter, then letters or digits '
        '(for example emailLabel).';

/// `null` when [name] is a valid class name, otherwise why it is not.
String? validateClassName(String name) => classNamePattern.hasMatch(name)
    ? null
    : 'Class names are PascalCase (for example ML, AppL10n).';

/// The file name the extension gives a module's ARB file.
String arbFileName(String module, String locale) => '${module}_$locale.arb';

/// Whether [key] is a translation, as opposed to `@@locale` or `@key`
/// metadata.
bool isTranslationKey(String key) => !key.startsWith('@');

/// Read an ARB file as an ordered map. Throws [FormatException] when the file
/// is not a JSON object.
Map<String, Object?> readArb(String path) {
  final json = readJsonFile(path);
  if (json is! Map<String, Object?>) {
    throw FormatException('${p.basename(path)} is not a JSON object');
  }
  return json;
}

/// Write [data] to [path] exactly as the extension does
/// (`JSON.stringify(data, null, 2)`, no trailing newline), creating parent
/// folders. Returns whether the file content changed.
bool writeArb(String path, Map<String, Object?> data) {
  final content = encodeJsonLikeJs(data);
  final file = File(path);
  if (file.existsSync() && file.readAsStringSync() == content) return false;
  file
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
  return true;
}

/// Copy of [data] with [oldKey] renamed to [newKey], keeping its position.
Map<String, Object?> renameMapKey(
  Map<String, Object?> data,
  String oldKey,
  String newKey,
) =>
    {
      for (final MapEntry(:key, :value) in data.entries)
        key == oldKey ? newKey : key: value,
    };
