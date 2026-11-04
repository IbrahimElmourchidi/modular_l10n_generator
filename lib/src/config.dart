/// Configuration read from the `modular_l10n:` section of `pubspec.yaml`,
/// the same section the VS Code extension reads, so a project configured
/// for one tool works with the other unchanged.
///
/// ```yaml
/// modular_l10n:
///   enabled: true
///   class_name: ML
///   default_locale: en
///   output_dir: lib/generated/modular_l10n
///   arb_dir_pattern: "**/l10n/*.arb"
///   generate_combined_arb: true
///   use_deferred_loading: false
///   log_level: warning   # silent | error | warning | verbose
///   module_access: part  # part | library
/// ```
///
/// Precedence, per key: command-line flag > `pubspec.yaml` > default.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Log verbosity, ordered from quietest to loudest.
enum LogLevel {
  /// Nothing at all.
  silent,

  /// Only failures.
  error,

  /// Failures, warnings, and a one-line summary (default).
  warning,

  /// Everything, including per-module progress.
  verbose;

  /// Parse a level, accepting the same aliases as the VS Code extension.
  /// Returns `null` for anything unrecognised.
  static LogLevel? tryParse(Object? value) {
    if (value is! String) return null;
    return switch (value.trim().toLowerCase()) {
      'silent' || 'none' || 'off' || 'quiet' => LogLevel.silent,
      'error' || 'errors' => LogLevel.error,
      'warn' || 'warning' || 'warnings' => LogLevel.warning,
      'verbose' || 'heavy' || 'debug' || 'all' || 'info' => LogLevel.verbose,
      _ => null,
    };
  }
}

/// How the per-module files relate to the generated entry-point library.
enum ModuleAccess {
  /// Every `<module>_l10n.dart` is a `part of` the entry point, so the entry
  /// point is the only way in.
  part,

  /// Each module file is its own library and can be imported directly.
  library;

  static ModuleAccess? tryParse(Object? value) => switch (value) {
        'part' => ModuleAccess.part,
        'library' => ModuleAccess.library,
        _ => null,
      };
}

/// Canonical form of a locale name: `zh-Hans` -> `zh_Hans`.
String normalizeLocale(String locale) => locale.trim().replaceAll('-', '_');

/// The configured default when the project's ARB files contain it, otherwise
/// the first detected locale. `null` when nothing was detected.
String? resolveEffectiveDefaultLocale(
  String configuredDefault,
  List<String> detectedLocales,
) {
  final wanted = normalizeLocale(configuredDefault);
  if (detectedLocales.contains(wanted)) return wanted;
  return detectedLocales.isEmpty ? null : detectedLocales.first;
}

/// A partial configuration: every field is optional, so sources can be
/// layered key by key.
class ConfigOverrides {
  const ConfigOverrides({
    this.enabled,
    this.className,
    this.defaultLocale,
    this.outputDir,
    this.arbFilePattern,
    this.generateCombinedArb,
    this.useDeferredLoading,
    this.logLevel,
    this.moduleAccess,
  });

  final bool? enabled;
  final String? className;
  final String? defaultLocale;
  final String? outputDir;
  final String? arbFilePattern;
  final bool? generateCombinedArb;
  final bool? useDeferredLoading;
  final LogLevel? logLevel;
  final ModuleAccess? moduleAccess;
}

/// The configuration a generation run uses.
class L10nConfig {
  const L10nConfig({
    this.enabled = true,
    this.className = 'ML',
    this.defaultLocale = 'en',
    this.outputDir = 'lib/generated/modular_l10n',
    this.arbFilePattern = '**/l10n/*.arb',
    this.generateCombinedArb = true,
    this.useDeferredLoading = false,
    this.logLevel = LogLevel.warning,
    this.moduleAccess = ModuleAccess.part,
  });

  final bool enabled;
  final String className;
  final String defaultLocale;

  /// Relative to the project root.
  final String outputDir;
  final String arbFilePattern;
  final bool generateCombinedArb;
  final bool useDeferredLoading;
  final LogLevel logLevel;
  final ModuleAccess moduleAccess;

  /// This config with every non-null field of [o] applied on top.
  L10nConfig apply(ConfigOverrides? o) {
    if (o == null) return this;
    return L10nConfig(
      enabled: o.enabled ?? enabled,
      className: o.className ?? className,
      defaultLocale: normalizeLocale(o.defaultLocale ?? defaultLocale),
      outputDir: o.outputDir ?? outputDir,
      arbFilePattern: o.arbFilePattern ?? arbFilePattern,
      generateCombinedArb: o.generateCombinedArb ?? generateCombinedArb,
      useDeferredLoading: o.useDeferredLoading ?? useDeferredLoading,
      logLevel: o.logLevel ?? logLevel,
      moduleAccess: o.moduleAccess ?? moduleAccess,
    );
  }
}

/// Raised when `pubspec.yaml` exists but cannot be parsed.
class PubspecException implements Exception {
  PubspecException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Flutter Intl's settings, read to detect conflicts with them.
typedef FlutterIntlConfig = ({String className, String outputDir});

/// Reads the `modular_l10n:` and `flutter_intl:` sections of a project's
/// `pubspec.yaml`.
class PubspecReader {
  PubspecReader(this.rootPath) : pubspecPath = p.join(rootPath, 'pubspec.yaml');

  final String rootPath;
  final String pubspecPath;

  bool get hasPubspec => File(pubspecPath).existsSync();

  YamlMap? _readDocument() {
    if (!hasPubspec) return null;
    final Object? doc;
    try {
      doc = loadYaml(File(pubspecPath).readAsStringSync());
    } on YamlException catch (e) {
      throw PubspecException('pubspec.yaml is not valid YAML: ${e.message}');
    }
    return doc is YamlMap ? doc : null;
  }

  /// The `modular_l10n:` section, or `null` when there is none.
  ///
  /// Values of the wrong type are ignored, so a typo falls back to the
  /// default instead of selecting a different file layout.
  ConfigOverrides? readConfig() {
    final section = _readDocument()?['modular_l10n'];
    if (section is! YamlMap) return null;

    return ConfigOverrides(
      enabled: _asBool(section['enabled']) ?? true,
      className: _asString(section['class_name']),
      defaultLocale: _asString(section['default_locale']) ??
          _asString(section['main_locale']),
      outputDir: _asString(section['output_dir']),
      arbFilePattern: _asString(section['arb_dir_pattern']),
      generateCombinedArb: _asBool(section['generate_combined_arb']),
      useDeferredLoading: _asBool(section['use_deferred_loading']),
      logLevel: LogLevel.tryParse(section['log_level']),
      moduleAccess: ModuleAccess.tryParse(section['module_access']),
    );
  }

  /// The `flutter_intl:` section with its defaults filled in, or `null` when
  /// the project does not configure Flutter Intl.
  FlutterIntlConfig? readFlutterIntlConfig() {
    final YamlMap? doc;
    try {
      doc = _readDocument();
    } on PubspecException {
      return null;
    }
    final section = doc?['flutter_intl'];
    if (section is! YamlMap) return null;
    return (
      className: _asString(section['class_name']) ?? 'S',
      outputDir: _asString(section['output_dir']) ?? 'lib/generated',
    );
  }

  static String? _asString(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static bool? _asBool(Object? value) => value is bool ? value : null;
}

/// Find the project root: the nearest directory at or above [start] that
/// contains a `pubspec.yaml`. Returns `null` when there is none.
String? findProjectRoot(String start) {
  var dir = p.normalize(p.absolute(start));
  while (true) {
    if (File(p.join(dir, 'pubspec.yaml')).existsSync()) return dir;
    final parent = p.dirname(dir);
    if (parent == dir) return null;
    dir = parent;
  }
}
