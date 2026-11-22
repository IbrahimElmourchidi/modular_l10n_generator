/// Edits the `modular_l10n:` section of `pubspec.yaml` in place, keeping
/// comments, formatting and every other section.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'project.dart' show OpException;

/// The `modular_l10n:` keys, in the order the extension writes them.
const modularConfigKeys = [
  'enabled',
  'class_name',
  'default_locale',
  'output_dir',
  'arb_dir_pattern',
  'generate_combined_arb',
  'use_deferred_loading',
  'watch_mode',
  'log_level',
  'module_access',
];

/// Set [values] under `modular_l10n:` in the project's `pubspec.yaml`.
///
/// Only the given keys change; the rest of the section and the file stay as
/// they are. A `null` value removes that key. Creates the section when it is
/// missing. Returns whether the file changed.
bool updateModularConfig(String rootPath, Map<String, Object?> values) {
  final file = File(p.join(rootPath, 'pubspec.yaml'));
  if (!file.existsSync()) {
    throw OpException('No pubspec.yaml in $rootPath.');
  }
  final original = file.readAsStringSync();
  final YamlEditor editor;
  try {
    editor = YamlEditor(original);
  } on YamlException catch (e) {
    throw OpException('pubspec.yaml is not valid YAML: ${e.message}');
  }

  final root = editor.parseAt([]);
  if (root is! YamlMap) {
    throw OpException('pubspec.yaml must be a YAML map.');
  }

  final section = root.nodes['modular_l10n'];
  if (section is! YamlMap) {
    final fresh = {
      for (final MapEntry(:key, :value) in values.entries)
        if (value != null) key: value,
    };
    if (fresh.isEmpty) return false;
    editor.update(['modular_l10n'], fresh);
  } else {
    for (final MapEntry(:key, :value) in values.entries) {
      if (value == null) {
        if (section.containsKey(key)) editor.remove(['modular_l10n', key]);
      } else if (section[key] != value) {
        editor.update(['modular_l10n', key], value);
      }
    }
  }

  final updated = editor.toString();
  if (updated == original) return false;
  file.writeAsStringSync(updated);
  return true;
}

/// The names of the project's `dependencies:` and `dev_dependencies:`.
({Set<String> dependencies, Set<String> devDependencies}) readDependencies(
  String rootPath,
) {
  final file = File(p.join(rootPath, 'pubspec.yaml'));
  Set<String> keys(Object? section) =>
      section is YamlMap ? section.keys.map((k) => '$k').toSet() : {};
  try {
    final doc = loadYaml(file.readAsStringSync());
    if (doc is! YamlMap) return (dependencies: {}, devDependencies: {});
    return (
      dependencies: keys(doc['dependencies']),
      devDependencies: keys(doc['dev_dependencies']),
    );
  } on Object {
    return (dependencies: {}, devDependencies: {});
  }
}
