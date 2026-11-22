/// Setting a project up and creating modules.
library;

import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../config.dart';
import '../dart_generator.dart' show toPascalCase, toSnakeCaseName;
import '../locales.dart';
import 'arb_file.dart';
import 'project.dart';
import 'pubspec_writer.dart';

/// `null` when [locale] is a locale the generator accepts, otherwise why not.
String? validateLocale(String locale) {
  final canonical = normalizeLocale(locale);
  if (canonical.isEmpty) return 'Enter a locale (for example en, ar, zh_Hans).';
  return isKnownLocale(canonical)
      ? null
      : 'Unknown locale "$canonical". Examples: en, en_US, ar_EG, zh_Hans_CN.';
}

/// Parse a comma- or space-separated locale list into canonical, de-duplicated
/// locales. Throws [OpException] for an unknown one.
List<String> parseLocaleList(String input) {
  final locales = <String>[];
  for (final raw in input.split(RegExp(r'[,\s]+'))) {
    if (raw.trim().isEmpty) continue;
    final error = validateLocale(raw);
    if (error != null) throw OpException(error);
    final locale = normalizeLocale(raw);
    if (!locales.contains(locale)) locales.add(locale);
  }
  if (locales.isEmpty) throw OpException('Enter at least one locale.');
  return locales;
}

/// The module name suggested for a folder: its name in snake_case.
String suggestModuleName(String folder) {
  final name = toSnakeCaseName(p.basename(folder))
      .replaceAll(RegExp('[^a-z0-9_]'), '_')
      .replaceAll(RegExp('_+'), '_')
      .replaceAll(RegExp(r'^[_0-9]+|_+$'), '');
  return name.isEmpty ? 'app' : name;
}

/// The starter key a new module gets: `<module>Title`.
String starterKey(String module) {
  final pascal = toPascalCase(module);
  return '${pascal[0].toLowerCase()}${pascal.substring(1)}Title';
}

/// Create the `l10n/` folder for a module in [folder] with one ARB file per
/// locale in [locales].
///
/// Each file gets `@@locale`, `@@context` and, unless [empty], a starter key
/// `<module>Title` whose default-locale value is `"<Module> Title"` (empty in
/// other locales). Existing files are skipped unless [overwrite].
OpResult createModule(
  Project project, {
  required String folder,
  required String name,
  required List<String> locales,
  bool empty = false,
  bool overwrite = false,
}) {
  final nameError = validateModuleName(name);
  if (nameError != null) throw OpException(nameError);
  if (locales.isEmpty) throw OpException('Choose at least one locale.');

  final dir = p.normalize(p.absolute(folder));
  if (!p.isWithin(project.rootPath, dir) && !p.equals(project.rootPath, dir)) {
    throw OpException('${p.relative(dir)} is outside the project.');
  }
  for (final m in project.modules) {
    if (m.name == name && !p.equals(project.l10nDir(m), p.join(dir, 'l10n'))) {
      throw OpException(
        'A module named "$name" already exists in '
        '${project.relative(project.l10nDir(m))}. Choose another name.',
      );
    }
  }

  final l10n = p.join(dir, 'l10n');
  final defaultLocale = locales.contains(project.defaultLocale)
      ? project.defaultLocale
      : locales.first;
  final result = OpResult();

  for (final raw in locales) {
    final locale = normalizeLocale(raw);
    final path = p.join(l10n, arbFileName(name, locale));
    if (File(path).existsSync() && !overwrite) {
      result.skipped.add('${project.relative(path)} (already exists)');
      continue;
    }
    final existed = File(path).existsSync();
    writeArb(path, {
      '@@locale': locale,
      '@@context': name,
      if (!empty)
        starterKey(name):
            locale == defaultLocale ? '${toPascalCase(name)} Title' : '',
    });
    (existed ? result.changed : result.created).add(path);
  }

  _warnIfUnmatched(project, l10n, result);
  return result;
}

/// Files outside the configured `arb_dir_pattern` are never scanned, so a
/// module created there would silently do nothing.
void _warnIfUnmatched(Project project, String l10nDir, OpResult result) {
  final probe = p.posix.joinAll(
    p.split(p.relative(p.join(l10nDir, 'x.arb'), from: project.rootPath)),
  );
  if (!Glob(project.config.arbFilePattern, context: p.posix).matches(probe)) {
    result.skipped.add(
      'warning: ${project.relative(l10nDir)} does not match arb_dir_pattern '
      '"${project.config.arbFilePattern}", so these files will not be generated',
    );
  }
}

/// Set up Modular L10n in a project: write the `modular_l10n:` section of
/// `pubspec.yaml` and create the first module.
OpResult initProject(
  String rootPath, {
  required String defaultLocale,
  required String moduleName,
  required String moduleFolder,
  String className = 'ML',
}) {
  final localeError = validateLocale(defaultLocale);
  if (localeError != null) throw OpException(localeError);
  final classError = validateClassName(className);
  if (classError != null) throw OpException(classError);
  final nameError = validateModuleName(moduleName);
  if (nameError != null) throw OpException(nameError);

  final locale = normalizeLocale(defaultLocale);
  final intl = PubspecReader(rootPath).readFlutterIntlConfig();
  if (intl != null && intl.className == className) {
    throw OpException(
      'Flutter Intl already uses the class name "$className" in this project. '
      'Choose another one (for example ML).',
    );
  }

  final result = OpResult();
  final pubspec = p.join(rootPath, 'pubspec.yaml');
  if (updateModularConfig(rootPath, {
    'enabled': true,
    'class_name': className,
    'default_locale': locale,
    'output_dir': 'lib/generated/modular_l10n',
  })) {
    result.changed.add(pubspec);
  }

  final project = Project.load(rootPath);
  final module = createModule(
    project,
    folder: moduleFolder,
    name: moduleName,
    locales: [locale],
  );
  result
    ..created.addAll(module.created)
    ..changed.addAll(module.changed)
    ..skipped.addAll(module.skipped);
  return result;
}
