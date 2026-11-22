/// Adding and removing locales across every module.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../config.dart';
import 'arb_file.dart';
import 'module_ops.dart' show validateLocale;
import 'project.dart';

/// Add [locale] to every module that does not have it yet.
///
/// The new file copies the module's default-locale file with every
/// translation emptied; `@key` metadata and `@@` attributes are kept, with
/// `@@locale` set to the new locale.
OpResult addLocale(Project project, String locale) {
  final error = validateLocale(locale);
  if (error != null) throw OpException(error);
  final canonical = normalizeLocale(locale);
  if (project.modules.isEmpty) {
    throw OpException('There are no modules yet. Create one first.');
  }

  final result = OpResult();
  for (final module in project.modules) {
    if (project.arbFile(module, canonical) != null) {
      result.skipped.add('${module.name} (already has "$canonical")');
      continue;
    }
    final template = project.arbFile(module, project.defaultLocale);
    Map<String, Object?> data = {
      '@@locale': canonical,
      '@@context': module.name,
    };
    if (template != null) {
      try {
        data = {
          for (final MapEntry(:key, :value) in readArb(template.path).entries)
            key: key == '@@locale'
                ? canonical
                : isTranslationKey(key)
                    ? ''
                    : value,
        };
      } on FormatException {
        // Keep the bare template.
      }
    }
    final path =
        p.join(project.l10nDir(module), arbFileName(module.name, canonical));
    if (File(path).existsSync()) {
      result.skipped.add('${project.relative(path)} (exists but is not '
          'recognised as "$canonical"; check its @@locale)');
      continue;
    }
    writeArb(path, data);
    result.created.add(path);
  }
  return result;
}

/// The ARB files [removeLocale] would delete.
List<String> filesForLocale(Project project, String locale) {
  final canonical = normalizeLocale(locale);
  return [
    for (final module in project.modules)
      if (project.arbFile(module, canonical) case final file?) file.path,
  ];
}

/// Delete [locale]'s ARB file from every module. The default locale cannot be
/// removed.
OpResult removeLocale(Project project, String locale) {
  final canonical = normalizeLocale(locale);
  if (canonical == project.defaultLocale) {
    throw OpException(
      '"$canonical" is the default locale and cannot be removed. '
      'Change default_locale in pubspec.yaml first.',
    );
  }
  if (!project.locales.contains(canonical)) {
    throw OpException(
      'No module has locale "$canonical". Locales: ${project.locales.join(', ')}.',
    );
  }
  final result = OpResult();
  for (final path in filesForLocale(project, canonical)) {
    File(path).deleteSync();
    result.deleted.add(path);
  }
  return result;
}
