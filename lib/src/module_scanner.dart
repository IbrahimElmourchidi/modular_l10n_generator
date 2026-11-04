/// Finds the project's modular ARB files and groups them by module.
///
/// A modular ARB file declares both `@@locale` and `@@context` (the module
/// name). Flutter Intl's `intl_*.arb` files are skipped, so both tools can
/// live in one project.
library;

import 'dart:convert';
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import 'collation.dart';
import 'config.dart';
import 'locales.dart';

/// One ARB file of a module.
class ArbFile {
  const ArbFile(this.path, this.locale, this.moduleName);

  /// Absolute path.
  final String path;
  final String locale;
  final String moduleName;
}

/// A module: every ARB file sharing one `@@context`.
class Module {
  Module(this.name, this.path);

  final String name;

  /// The directory above the module's `l10n/` folder.
  final String path;
  final List<ArbFile> arbFiles = [];
}

/// The outcome of [ModuleScanner.scan].
class ScanResult {
  const ScanResult({
    required this.modules,
    required this.detectedLocales,
    required this.validationErrors,
    required this.warnings,
    required this.skippedFlutterIntlFiles,
  });

  final List<Module> modules;

  /// Sorted.
  final List<String> detectedLocales;

  /// Files that could not be used, one message per problem.
  final List<String> validationErrors;

  /// Problems that did not stop a file from being used.
  final List<String> warnings;

  /// Relative paths of `intl_*.arb` files that were ignored.
  final List<String> skippedFlutterIntlFiles;
}

/// Directory names that never contain hand-authored ARB files, matched as
/// whole path segments so `generated_reports/` or `build_order/` still count.
const excludedDirectories = {
  'generated',
  '.dart_tool',
  'build',
  'node_modules',
  '.git',
  '.idea',
  '.vscode',
  'output',
  'outputs',
  'dist',
  'tmp',
};

/// True when any directory segment of [filePath] *below* [rootPath] is
/// excluded. Where the project lives on disk is not our business.
bool isInExcludedDirectory(String filePath, String rootPath) {
  final relative = p.relative(filePath, from: rootPath);
  if (relative.startsWith('..') || p.isAbsolute(relative)) return false;
  final segments = p.split(relative);
  return segments.take(segments.length - 1).any(excludedDirectories.contains);
}

final _flutterIntlFile = RegExp(r'^intl_.*\.arb$');
final _moduleName = RegExp(r'^[a-z][a-z0-9_]*$');

/// Whether [filePath] is a Flutter Intl ARB file (`intl_*.arb`).
bool isFlutterIntlFile(String filePath) =>
    _flutterIntlFile.hasMatch(p.basename(filePath));

/// Decode an ARB file, tolerating a UTF-8 byte-order mark.
Object? readJsonFile(String filePath) {
  var content = File(filePath).readAsStringSync();
  if (content.startsWith('﻿')) content = content.substring(1);
  return jsonDecode(content);
}

class ModuleScanner {
  ModuleScanner(this.rootPath, this.arbPattern);

  final String rootPath;
  final String arbPattern;

  ScanResult scan() {
    final modules = <String, Module>{};
    final detectedLocales = <String>{};
    final validationErrors = <String>[];
    final warnings = <String>[];
    final skipped = <String>[];

    for (final arbPath in findArbFiles()) {
      if (isFlutterIntlFile(arbPath)) {
        skipped.add(_relative(arbPath));
        continue;
      }

      final result = _validate(arbPath);
      for (final warning in result.warnings) {
        warnings.add('${_relative(arbPath)}: $warning');
      }
      if (result.errors.isNotEmpty) {
        validationErrors
            .addAll(result.errors.map((e) => '${_relative(arbPath)}: $e'));
        continue;
      }

      final moduleName = result.moduleName!;
      final locale = result.locale!;
      detectedLocales.add(locale);
      modules
          .putIfAbsent(moduleName,
              () => Module(moduleName, p.dirname(p.dirname(arbPath))))
          .arbFiles
          .add(ArbFile(arbPath, locale, moduleName));
    }

    _reportLocaleCollisions(modules.values, warnings);

    return ScanResult(
      modules: modules.values.toList(),
      detectedLocales: detectedLocales.toList()..sort(),
      validationErrors: validationErrors,
      warnings: warnings,
      skippedFlutterIntlFiles: skipped,
    );
  }

  /// Every file under the root matching [arbPattern], outside excluded and
  /// hidden directories, in the order the VS Code extension sees them.
  List<String> findArbFiles() {
    final glob = Glob(arbPattern, context: p.posix);
    final found = <String>[];

    void walk(Directory dir) {
      final List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final entity in entries) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        if (entity is Directory) {
          if (!excludedDirectories.contains(name)) walk(entity);
        } else if (entity is File ||
            (entity is Link && FileSystemEntity.isFileSync(entity.path))) {
          // A symlinked file counts; a symlinked directory is not crawled,
          // which avoids cycles.
          final relative =
              p.split(p.relative(entity.path, from: rootPath)).join('/');
          if (glob.matches(relative)) {
            found.add(p.normalize(entity.absolute.path));
          }
        }
      }
    }

    walk(Directory(rootPath));
    return found..sort(collate);
  }

  /// Two files in one module that resolve to the same locale once
  /// normalised: only one of them would be read.
  void _reportLocaleCollisions(
      Iterable<Module> modules, List<String> warnings) {
    for (final module in modules) {
      final seen = <String, String>{};
      for (final file in module.arbFiles) {
        final previous = seen[file.locale];
        if (previous != null) {
          warnings.add(
            '${_relative(file.path)} and $previous both resolve to locale '
            '"${file.locale}" in module "${module.name}"; only one will be used.',
          );
        } else {
          seen[file.locale] = _relative(file.path);
        }
      }
    }
  }

  ({
    String? moduleName,
    String? locale,
    List<String> errors,
    List<String> warnings
  }) _validate(String arbPath) {
    final errors = <String>[];
    final warnings = <String>[];

    final Object? json;
    try {
      json = readJsonFile(arbPath);
    } on FormatException {
      return (
        moduleName: null,
        locale: null,
        errors: ['Invalid JSON syntax'],
        warnings: warnings
      );
    } on FileSystemException catch (e) {
      return (
        moduleName: null,
        locale: null,
        errors: ['Error reading file: ${e.message}'],
        warnings: warnings,
      );
    }

    if (json is! Map<String, Object?>) {
      return (
        moduleName: null,
        locale: null,
        errors: ['An ARB file must be a JSON object'],
        warnings: warnings,
      );
    }

    final rawLocale = json['@@locale'];
    final moduleName = json['@@context'];
    final locale = rawLocale is String ? normalizeLocale(rawLocale) : null;

    if (rawLocale == null || (rawLocale is String && locale!.isEmpty)) {
      errors.add(
          'Missing required property "@@locale" (required for Modular L10n)');
    } else if (rawLocale is! String) {
      errors.add('"@@locale" must be a string');
    } else if (!isKnownLocale(locale!)) {
      errors.add(
        'Invalid or unknown locale "$locale". '
        'Valid examples: en, en_US, zh_Hans_CN, ar_EG, sr_Latn_RS',
      );
    } else if (locale != rawLocale) {
      warnings.add(
        '"@@locale": "$rawLocale" is not in canonical form; treating it as '
        '"$locale". Use "$locale" so it matches the default-locale setting.',
      );
    }

    if (moduleName == null || moduleName == '') {
      errors.add(
        'Missing required property "@@context" (required for Modular L10n '
        'to distinguish from Flutter Intl files)',
      );
    } else if (moduleName is! String) {
      errors.add('"@@context" must be a string');
    } else if (!_moduleName.hasMatch(moduleName)) {
      errors.add(
        'Invalid module name "$moduleName". Must be snake_case '
        '(e.g., auth, user_profile, home_screen)',
      );
    }

    if (errors.isNotEmpty) {
      return (
        moduleName: null,
        locale: null,
        errors: errors,
        warnings: const []
      );
    }
    return (
      moduleName: moduleName as String,
      locale: locale,
      errors: const [],
      warnings: warnings,
    );
  }

  String _relative(String fullPath) => p.relative(fullPath, from: rootPath);
}
