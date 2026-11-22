/// Sorting, renaming and removing keys.
library;

import 'dart:io';

import '../collation.dart';
import '../dart_generator.dart' show toCamelCase;
import 'arb_file.dart';
import 'project.dart';

/// [data] in canonical order: `@@locale`, `@@context`, `@@last_modified`,
/// other `@@` attributes, then translation keys alphabetically, each
/// followed by its `@key` metadata. Orphaned `@key` entries go last.
Map<String, Object?> sortArbData(Map<String, Object?> data) {
  final result = <String, Object?>{};
  for (final meta in const ['@@locale', '@@context', '@@last_modified']) {
    if (data.containsKey(meta)) result[meta] = data[meta];
  }
  for (final key in data.keys) {
    if (key.startsWith('@@')) result.putIfAbsent(key, () => data[key]);
  }
  final keys = data.keys.where(isTranslationKey).toList()..sort(collate);
  for (final key in keys) {
    result[key] = data[key];
    if (data.containsKey('@$key')) result['@$key'] = data['@$key'];
  }
  for (final key in data.keys) {
    result.putIfAbsent(key, () => data[key]);
  }
  return result;
}

/// The ARB files of [module] (or of every module), with their modules.
Iterable<String> _arbPaths(Project project, String? module) => [
      for (final m
          in module == null ? project.modules : [project.module(module)])
        for (final f in m.arbFiles) f.path,
    ];

/// Sort the keys of every ARB file (or [module]'s). With [dryRun], report the
/// files that are out of order without changing them.
OpResult sortArbFiles(Project project, {String? module, bool dryRun = false}) {
  final result = OpResult();
  for (final path in _arbPaths(project, module)) {
    final data = readArb(path);
    final sorted = sortArbData(data);
    if (dryRun) {
      if (!_sameKeyOrder(data, sorted)) result.changed.add(path);
    } else if (writeArb(path, sorted)) {
      result.changed.add(path);
    }
  }
  return result;
}

bool _sameKeyOrder(Map<String, Object?> a, Map<String, Object?> b) {
  final keysA = a.keys.toList(), keysB = b.keys.toList();
  for (var i = 0; i < keysA.length; i++) {
    if (keysA[i] != keysB[i]) return false;
  }
  return true;
}

/// A Dart file where a rename replaces references.
class DartEdit {
  DartEdit(this.path, this.lines);
  final String path;

  /// 1-based line numbers that change.
  final List<int> lines;
}

/// The regex that finds `.<camelModule>.<key>` references in Dart code.
RegExp keyReference(String module, String key) => RegExp(
    '\\.${RegExp.escape(toCamelCase(module))}\\.${RegExp.escape(key)}\\b');

/// Rename [oldKey] to [newKey] in every locale file of [module], keeping its
/// position and its `@key` metadata, and update references in the app's Dart
/// files. With [dryRun], only report what would change.
({OpResult result, List<DartEdit> dartEdits}) renameKey(
  Project project, {
  required String module,
  required String oldKey,
  required String newKey,
  bool dryRun = false,
}) {
  final error = validateKeyName(newKey);
  if (error != null) throw OpException(error);
  if (oldKey == newKey) {
    throw OpException('The new name is the same as the old one.');
  }
  final m = project.module(module);

  var found = false;
  for (final file in m.arbFiles) {
    final data = readArb(file.path);
    if (data.containsKey(newKey)) {
      throw OpException(
          'Key "$newKey" already exists in ${project.relative(file.path)}.');
    }
    found = found || data.containsKey(oldKey);
  }
  if (!found) throw OpException('Module "$module" has no key "$oldKey".');

  final result = OpResult();
  for (final file in m.arbFiles) {
    final data = readArb(file.path);
    if (!data.containsKey(oldKey)) continue;
    final renamed = renameMapKey(
        renameMapKey(data, oldKey, newKey), '@$oldKey', '@$newKey');
    if (!dryRun) writeArb(file.path, renamed);
    result.changed.add(file.path);
  }

  final pattern = keyReference(module, oldKey);
  final replacement = '.${toCamelCase(module)}.$newKey';
  final edits = <DartEdit>[];
  for (final path in project.dartSourceFiles()) {
    final content = File(path).readAsStringSync();
    if (!pattern.hasMatch(content)) continue;
    final lines = content.split('\n');
    edits.add(DartEdit(path, [
      for (var i = 0; i < lines.length; i++)
        if (pattern.hasMatch(lines[i])) i + 1,
    ]));
    if (!dryRun) {
      File(path).writeAsStringSync(content.replaceAll(pattern, replacement));
    }
    result.changed.add(path);
  }
  return (result: result, dartEdits: edits);
}

/// Default-locale keys of each module that no Dart file under `lib/`
/// references as `.<camelModule>.<key>`. Keys used dynamically can show up
/// here, so the result is a list to review, not proof.
Map<String, List<String>> findUnusedKeys(Project project) {
  final code = StringBuffer();
  for (final path in project.dartSourceFiles()) {
    try {
      code.writeln(File(path).readAsStringSync());
    } on FileSystemException {
      // Unreadable files cannot reference anything.
    }
  }
  final source = code.toString();
  final unused = <String, List<String>>{};
  for (final module in project.modules) {
    final file = project.arbFile(module, project.defaultLocale);
    if (file == null) continue;
    final keys = [
      for (final key in readArb(file.path).keys.where(isTranslationKey))
        if (!keyReference(module.name, key).hasMatch(source)) key,
    ];
    if (keys.isNotEmpty) unused[module.name] = keys;
  }
  return unused;
}

/// Remove [keys] (module → keys) and their `@key` metadata from every
/// locale file.
OpResult removeKeys(Project project, Map<String, List<String>> keys) {
  final result = OpResult();
  for (final MapEntry(key: module, value: names) in keys.entries) {
    for (final file in project.module(module).arbFiles) {
      final data = readArb(file.path);
      for (final name in names) {
        data
          ..remove(name)
          ..remove('@$name');
      }
      if (writeArb(file.path, data)) result.changed.add(file.path);
    }
  }
  return result;
}
