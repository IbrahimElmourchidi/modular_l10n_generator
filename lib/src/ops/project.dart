/// A loaded project: its configuration and its modules, read once and shared
/// by every command.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../config.dart';
import '../generate.dart';
import '../logger.dart';
import '../module_scanner.dart';

/// A user-facing failure of a command: bad input, or a project state the
/// command cannot work with. The message is meant to be shown as is.
class OpException implements Exception {
  OpException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What a command did to the file system, for reporting.
class OpResult {
  final List<String> created = [];
  final List<String> changed = [];
  final List<String> deleted = [];

  /// Files left alone, with the reason.
  final List<String> skipped = [];

  /// Set when the command regenerated the Dart code afterwards.
  GenerationResult? generation;

  bool get touchedFiles =>
      created.isNotEmpty || changed.isNotEmpty || deleted.isNotEmpty;

  /// Report every entry through [logger], with paths relative to [root].
  void report(Logger logger, String root) {
    String rel(String path) =>
        p.isAbsolute(path) ? p.relative(path, from: root) : path;
    for (final f in created) {
      logger.summary('  created  ${rel(f)}');
    }
    for (final f in changed) {
      logger.summary('  updated  ${rel(f)}');
    }
    for (final f in deleted) {
      logger.summary('  deleted  ${rel(f)}');
    }
    for (final f in skipped) {
      logger.summary('  skipped  $f');
    }
  }
}

/// A project's effective configuration and scanned modules.
class Project {
  Project._(this.rootPath, this.config, this.scan, this.overrides);

  /// Read the configuration and scan the ARB files of the project at
  /// [rootPath]. Throws [OpException] when `pubspec.yaml` is invalid.
  factory Project.load(String rootPath, {ConfigOverrides? overrides}) {
    final L10nConfig config;
    try {
      config = loadConfig(rootPath, overrides: overrides);
    } on PubspecException catch (e) {
      throw OpException(e.message);
    }
    final scan = ModuleScanner(rootPath, config.arbFilePattern).scan();
    return Project._(rootPath, config, scan, overrides);
  }

  final String rootPath;
  final L10nConfig config;
  final ScanResult scan;

  /// Command-line overrides, kept so a reload and a regeneration see them.
  final ConfigOverrides? overrides;

  List<Module> get modules => scan.modules;
  List<String> get locales => scan.detectedLocales;

  /// The locale that serves as the template: the configured default when the
  /// ARB files contain it, otherwise the first detected locale.
  String get defaultLocale =>
      resolveEffectiveDefaultLocale(config.defaultLocale, locales) ??
      normalizeLocale(config.defaultLocale);

  /// A fresh copy, after files changed on disk.
  Project reload() => Project.load(rootPath, overrides: overrides);

  /// The module named [name]. Throws [OpException] when there is none.
  Module module(String name) {
    for (final m in modules) {
      if (m.name == name) return m;
    }
    final known = modules.map((m) => m.name).join(', ');
    throw OpException(
      'No module named "$name".'
      '${known.isEmpty ? ' There are no modules yet.' : ' Modules: $known.'}',
    );
  }

  /// [module]'s ARB file for [locale], or `null` when it has none.
  ArbFile? arbFile(Module module, String locale) {
    for (final f in module.arbFiles) {
      if (f.locale == locale) return f;
    }
    return null;
  }

  /// The folder that holds [module]'s ARB files.
  String l10nDir(Module module) => module.arbFiles.isEmpty
      ? p.join(module.path, 'l10n')
      : p.dirname(module.arbFiles.first.path);

  String relative(String path) => p.relative(path, from: rootPath);

  /// Absolute path of the generated output folder.
  String get outputPath => p.normalize(p.join(rootPath, config.outputDir));

  /// The app's own Dart files under `lib/`: generated code (the output folder,
  /// anything under a `generated` folder, and `.g.dart`, `.freezed.dart`,
  /// `.gr.dart` files) is left out.
  List<String> dartSourceFiles() {
    final lib = Directory(p.join(rootPath, 'lib'));
    if (!lib.existsSync()) return const [];
    final files = <String>[];
    for (final entity in lib.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (isGeneratedDartFile(entity.path)) continue;
      if (p.isWithin(outputPath, p.normalize(entity.path))) continue;
      files.add(p.normalize(entity.path));
    }
    return files..sort();
  }

  /// Run code generation with this project's settings.
  GenerationResult regenerate(Logger logger, {bool force = false}) =>
      runGeneration(
        rootPath: rootPath,
        logger: logger,
        overrides: overrides,
        force: force,
      );
}

final _generatedSuffix = RegExp(r'\.(g|freezed|gr)\.dart$');

/// Whether [path] is generated Dart code that commands must not scan or edit.
bool isGeneratedDartFile(String path) =>
    _generatedSuffix.hasMatch(path) || p.split(path).contains('generated');
