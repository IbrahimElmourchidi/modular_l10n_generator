/// Adding translation keys.
library;

import 'arb_file.dart';
import 'project.dart';

/// A placeholder declared in a key's `@key` metadata.
class PlaceholderSpec {
  const PlaceholderSpec(this.name, [this.type = 'String']);

  /// Parse `name` or `name:type`.
  factory PlaceholderSpec.parse(String spec) {
    final parts = spec.split(':');
    final name = parts.first.trim();
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) {
      throw OpException('Invalid placeholder name "$name".');
    }
    final type = parts.length > 1 && parts[1].trim().isNotEmpty
        ? parts[1].trim()
        : 'String';
    return PlaceholderSpec(name, type);
  }

  final String name;
  final String type;
}

/// The keys of [module]'s default-locale file, in file order.
List<String> moduleKeys(Project project, String module) {
  final m = project.module(module);
  final file = project.arbFile(m, project.defaultLocale) ??
      (m.arbFiles.isEmpty ? null : m.arbFiles.first);
  if (file == null) return const [];
  return readArb(file.path).keys.where(isTranslationKey).toList();
}

/// Add [key] to every locale file of [module].
///
/// [values] maps locale to text; a locale without a value gets `""`.
/// [description] and [placeholders] go into `@key` in the default-locale
/// file. Refuses a key that already exists in the module.
OpResult addKey(
  Project project, {
  required String module,
  required String key,
  Map<String, String> values = const {},
  String? description,
  List<PlaceholderSpec> placeholders = const [],
}) {
  final error = validateKeyName(key);
  if (error != null) throw OpException(error);
  final m = project.module(module);
  for (final file in m.arbFiles) {
    if (readArb(file.path).containsKey(key)) {
      throw OpException(
        'Key "$key" already exists in ${project.relative(file.path)}. '
        'Use rename-key or pick another name.',
      );
    }
  }
  for (final locale in values.keys) {
    if (project.arbFile(m, locale) == null) {
      throw OpException('Module "$module" has no "$locale" file.');
    }
  }

  final result = OpResult();
  for (final file in m.arbFiles) {
    final data = readArb(file.path);
    data[key] = values[file.locale] ?? '';
    final hasMeta = (description != null && description.isNotEmpty) ||
        placeholders.isNotEmpty;
    if (file.locale == project.defaultLocale && hasMeta) {
      data['@$key'] = {
        if (description != null && description.isNotEmpty)
          'description': description,
        if (placeholders.isNotEmpty)
          'placeholders': {
            for (final ph in placeholders) ph.name: {'type': ph.type},
          },
      };
    }
    if (writeArb(file.path, data)) result.changed.add(file.path);
  }
  return result;
}

/// Set one translation: [key] of [module] in [locale].
OpResult setTranslation(
  Project project, {
  required String module,
  required String locale,
  required String key,
  required String value,
}) {
  final m = project.module(module);
  final file = project.arbFile(m, locale) ??
      (throw OpException('Module "$module" has no "$locale" file.'));
  final data = readArb(file.path);
  data[key] = value;
  final result = OpResult();
  if (writeArb(file.path, data)) result.changed.add(file.path);
  return result;
}

/// Keys of the default locale that are missing or empty in [locale], as
/// (module, key, template text) in module and file order.
List<({String module, String key, String template})> untranslatedKeys(
  Project project,
  String locale,
) {
  final out = <({String module, String key, String template})>[];
  for (final m in project.modules) {
    final template = project.arbFile(m, project.defaultLocale);
    final target = project.arbFile(m, locale);
    if (template == null || target == null) continue;
    final base = readArb(template.path);
    final data = readArb(target.path);
    for (final key in base.keys.where(isTranslationKey)) {
      final value = data[key];
      if (value == null || (value is String && value.trim().isEmpty)) {
        out.add((module: m.name, key: key, template: '${base[key]}'));
      }
    }
  }
  return out;
}
