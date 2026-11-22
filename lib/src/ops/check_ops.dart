/// Project checks: missing and empty translations, ICU problems, and direct
/// imports of generated module files.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../config.dart';
import '../dart_generator.dart' show toSnakeCaseName;
import '../icu/icu_diagnostics.dart';
import '../icu/icu_parser.dart';
import '../icu/icu_types.dart';
import 'arb_file.dart';
import 'project.dart';

enum IssueSeverity { error, warning, info }

/// One problem found by [checkProject].
class Issue {
  const Issue({
    required this.severity,
    required this.code,
    required this.message,
    this.file,
    this.line,
    this.module,
    this.locale,
    this.key,
  });

  final IssueSeverity severity;

  /// Stable identifier, the same as the extension's diagnostic codes.
  final String code;
  final String message;

  /// Absolute path, when the issue belongs to a file.
  final String? file;

  /// 1-based line, when known.
  final int? line;
  final String? module;
  final String? locale;
  final String? key;
}

/// Run every check. ICU hints are included only when [hints] is true.
List<Issue> checkProject(Project project, {bool hints = false}) {
  final issues = <Issue>[];
  for (final message in project.scan.validationErrors) {
    issues.add(Issue(
        severity: IssueSeverity.error, code: 'invalid-arb', message: message));
  }
  for (final message in project.scan.warnings) {
    issues.add(
        Issue(severity: IssueSeverity.warning, code: 'scan', message: message));
  }
  if (!project.locales
          .contains(normalizeLocale(project.config.defaultLocale)) &&
      project.locales.isNotEmpty) {
    issues.add(Issue(
      severity: IssueSeverity.warning,
      code: 'default-locale',
      message: 'Configured default locale "${project.config.defaultLocale}" '
          'is not in the ARB files; "${project.defaultLocale}" is used.',
    ));
  }

  final template = project.defaultLocale;
  for (final module in project.modules) {
    final templateFile = project.arbFile(module, template);
    if (templateFile == null) {
      issues.add(Issue(
        severity: IssueSeverity.error,
        code: 'missing-locale-file',
        message:
            'Module "${module.name}" has no "$template" (default locale) file.',
        module: module.name,
        locale: template,
      ));
      continue;
    }
    final Map<String, Object?> templateData;
    try {
      templateData = readArb(templateFile.path);
    } on FormatException {
      continue;
    }
    final templateValues = {
      for (final MapEntry(:key, :value) in templateData.entries)
        if (isTranslationKey(key) && value is String) key: value,
    };
    final canonical = {
      for (final MapEntry(:key, :value) in templateValues.entries)
        key: buildCanonicalArgs(
          collectArgs(parseIcu(value).nodes),
          (name) => _declaredType(templateData, key, name),
        ),
    };

    void icu(String path, Map<String, Object?> data, String locale) {
      final lines = _LineFinder(path);
      for (final MapEntry(:key, :value) in data.entries) {
        if (!isTranslationKey(key) || value is! String) continue;
        for (final d in diagnoseIcuMessage(key, value,
            template: templateValues[key], canonicalArgs: canonical[key])) {
          if (d.severity == IcuSeverity.hint && !hints) continue;
          issues.add(Issue(
            severity: switch (d.severity) {
              IcuSeverity.error => IssueSeverity.error,
              IcuSeverity.warning => IssueSeverity.warning,
              IcuSeverity.hint => IssueSeverity.info,
            },
            code: d.code,
            message: '"$key": ${d.message}',
            file: path,
            line: lines.lineOf(key),
            module: module.name,
            locale: locale,
            key: key,
          ));
        }
      }
    }

    icu(templateFile.path, templateData, template);

    for (final locale in project.locales) {
      if (locale == template) continue;
      final file = project.arbFile(module, locale);
      if (file == null) {
        issues.add(Issue(
          severity: IssueSeverity.error,
          code: 'missing-locale-file',
          message: 'Module "${module.name}" has no "$locale" file '
              '(${templateValues.length} key(s) untranslated).',
          module: module.name,
          locale: locale,
        ));
        continue;
      }
      final Map<String, Object?> data;
      try {
        data = readArb(file.path);
      } on FormatException {
        continue;
      }
      final lines = _LineFinder(file.path);
      for (final key in templateData.keys.where(isTranslationKey)) {
        final value = data[key];
        if (value == null) {
          issues.add(Issue(
            severity: IssueSeverity.error,
            code: 'missing-translation',
            message: 'Missing "$key" (exists in $template).',
            file: file.path,
            module: module.name,
            locale: locale,
            key: key,
          ));
        } else if (value is String && value.trim().isEmpty) {
          issues.add(Issue(
            severity: IssueSeverity.warning,
            code: 'empty-translation',
            message: 'Empty "$key" ($template: "${templateData[key]}").',
            file: file.path,
            line: lines.lineOf(key),
            module: module.name,
            locale: locale,
            key: key,
          ));
        }
      }
      icu(file.path, data, locale);
    }
  }

  issues.addAll(findDirectImports(project));
  return issues;
}

String? _declaredType(Map<String, Object?> data, String key, String name) {
  final meta = data['@$key'];
  if (meta is! Map) return null;
  final placeholders = meta['placeholders'];
  if (placeholders is! Map) return null;
  final ph = placeholders[name];
  if (ph is! Map) return null;
  final type = ph['type'];
  return type is String ? type : null;
}

/// Finds the line of a top-level key in a JSON file, for reporting.
class _LineFinder {
  _LineFinder(String path) {
    try {
      _lines = File(path).readAsLinesSync();
    } on FileSystemException {
      _lines = const [];
    }
  }

  late final List<String> _lines;

  int? lineOf(String key) {
    final needle = '"${key.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
    for (var i = 0; i < _lines.length; i++) {
      final t = _lines[i].trimLeft();
      if (t.startsWith(needle) &&
          t.substring(needle.length).trimLeft().startsWith(':')) {
        return i + 1;
      }
    }
    return null;
  }
}

final _moduleFile = RegExp(r'^[a-z0-9_]+_l10n\.dart$');
final _directive = RegExp(
    r'''^[ \t]*(?:import|export|part)\s+['"]([^'"]+)['"]''',
    multiLine: true);

/// Imports of `<module>_l10n.dart` files that bypass the generated entry
/// point. Only reported with `module_access: part`, where they do not compile.
List<Issue> findDirectImports(Project project) {
  if (project.config.moduleAccess != ModuleAccess.part) return const [];
  final entry = '${toSnakeCaseName(project.config.className)}.dart';
  final out = project.outputPath;
  final lib = p.join(project.rootPath, 'lib');
  final issues = <Issue>[];

  for (final file in project.dartSourceFiles()) {
    final String text;
    try {
      text = File(file).readAsStringSync();
    } on FileSystemException {
      continue;
    }
    for (final match in _directive.allMatches(text)) {
      final uri = match[1]!;
      String? absolute;
      if (uri.startsWith('package:')) {
        final segments = uri.substring('package:'.length).split('/');
        if (segments.length < 2) continue;
        absolute = p.joinAll([lib, ...segments.skip(1)]);
      } else if (!uri.contains(':')) {
        absolute = p.normalize(p.join(p.dirname(file), uri));
      }
      if (absolute == null || !p.equals(p.dirname(absolute), out)) continue;
      final name = p.basename(absolute);
      if (!_moduleFile.hasMatch(name)) continue;
      issues.add(Issue(
        severity: IssueSeverity.warning,
        code: 'direct-module-import',
        message: "Do not import '$name' directly. Import '$entry' and read "
            'strings through ${project.config.className}.of(context).<module>.',
        file: file,
        line: '\n'.allMatches(text.substring(0, match.start)).length + 1,
      ));
    }
  }
  return issues;
}
