/// One full generation run: read config, scan ARB files, parse, generate.
library;

import 'package:path/path.dart' as p;

import 'arb_parser.dart';
import 'config.dart';
import 'dart_generator.dart';
import 'logger.dart';
import 'module_scanner.dart';

/// The outcome of [runGeneration].
class GenerationResult {
  const GenerationResult({
    required this.success,
    this.skipped = false,
    this.config,
    this.moduleCount = 0,
    this.keyCount = 0,
    this.locales = const [],
    this.writtenFiles = const [],
    this.warningCount = 0,
  });

  /// Whether generation completed. A run with warnings still succeeds.
  final bool success;

  /// True when `modular_l10n.enabled: false` turned the run into a no-op.
  final bool skipped;

  /// The effective configuration, when it could be read.
  final L10nConfig? config;
  final int moduleCount;
  final int keyCount;
  final List<String> locales;

  /// Files whose content changed.
  final List<String> writtenFiles;

  /// Warnings and validation errors reported during the run.
  final int warningCount;
}

/// Read the effective configuration for the project at [rootPath]:
/// [overrides] (command-line flags) over `pubspec.yaml` over defaults.
L10nConfig loadConfig(String rootPath, {ConfigOverrides? overrides}) {
  final pubspec = PubspecReader(rootPath).readConfig();
  return const L10nConfig().apply(pubspec).apply(overrides);
}

/// Generate localizations for the project at [rootPath].
///
/// Never throws: failures are logged and reported through
/// [GenerationResult.success]. When [force] is false, a configuration that
/// would collide with Flutter Intl's generated code is refused.
GenerationResult runGeneration({
  required String rootPath,
  required Logger logger,
  ConfigOverrides? overrides,
  bool force = false,
  DateTime? today,
}) {
  final L10nConfig config;
  try {
    config = loadConfig(rootPath, overrides: overrides);
  } on PubspecException catch (e) {
    logger.error(e.message);
    return const GenerationResult(success: false);
  }
  logger.level = config.logLevel;

  if (!config.enabled) {
    logger.summary(
      'Modular L10n is disabled (modular_l10n.enabled: false in pubspec.yaml); nothing generated.',
    );
    return GenerationResult(success: true, skipped: true, config: config);
  }

  var warningCount = 0;
  void warn(String message) {
    warningCount++;
    logger.warn(message);
  }

  if (!_checkFlutterIntlConflicts(rootPath, config, logger, force, warn)) {
    return GenerationResult(success: false, config: config);
  }

  try {
    logger.verbose('Scanning ${p.join(rootPath, config.arbFilePattern)}');
    final scan = ModuleScanner(rootPath, config.arbFilePattern).scan();

    for (final skipped in scan.skippedFlutterIntlFiles) {
      logger.verbose('Skipping Flutter Intl file: $skipped');
    }
    scan.warnings.forEach(warn);
    scan.validationErrors.forEach(warn);

    if (scan.modules.isEmpty) {
      logger.error(
        'No valid ARB files found matching "${config.arbFilePattern}".\n'
        'Each ARB file needs both "@@locale" and "@@context" (the module name):\n'
        '  {\n'
        '    "@@locale": "en",\n'
        '    "@@context": "auth",\n'
        '    "emailLabel": "Email"\n'
        '  }',
      );
      return GenerationResult(
          success: false, config: config, warningCount: warningCount);
    }

    final locales = scan.detectedLocales;
    logger.verbose('Found ${scan.modules.length} module(s):');
    for (final module in scan.modules) {
      logger.verbose(
          '  ${module.name} [${module.arbFiles.map((f) => f.locale).join(', ')}]');
    }

    final defaultLocale =
        resolveEffectiveDefaultLocale(config.defaultLocale, locales) ??
            config.defaultLocale;
    if (!locales.contains(config.defaultLocale)) {
      warn(
        'Configured default locale "${config.defaultLocale}" not found in ARB files; '
        'using "$defaultLocale".',
      );
    }
    logger.verbose('Locales: ${locales.join(', ')} (default: $defaultLocale)');

    final parsed = ArbParser(onWarning: warn)
        .parseModules(scan.modules, defaultLocale: defaultLocale);

    final written = DartGenerator(GeneratorConfig(
      outputPath: p.join(rootPath, config.outputDir),
      className: config.className,
      defaultLocale: defaultLocale,
      supportedLocales: locales,
      generateCombinedArb: config.generateCombinedArb,
      useDeferredLoading: config.useDeferredLoading,
      moduleAccess: config.moduleAccess,
      onWarning: warn,
      today: today,
    )).generate(parsed);

    for (final file in written) {
      logger.verbose('  wrote ${p.relative(file, from: rootPath)}');
    }

    final keyCount = parsed.fold<int>(0, (sum, m) => sum + m.keys.length);
    final changed =
        written.isEmpty ? 'no changes' : '${written.length} file(s) updated';
    logger.summary(
      'Generated $keyCount key(s) · ${scan.modules.length} module(s) · '
      '${locales.length} locale(s) [${locales.join(', ')}] → ${config.outputDir} ($changed)',
    );

    return GenerationResult(
      success: true,
      config: config,
      moduleCount: scan.modules.length,
      keyCount: keyCount,
      locales: locales,
      writtenFiles: written,
      warningCount: warningCount,
    );
  } on Object catch (error, stack) {
    logger.error('Generation failed: $error');
    logger.verbose('$stack');
    return GenerationResult(
        success: false, config: config, warningCount: warningCount);
  }
}

/// Refuse settings that would make our output collide with Flutter Intl's,
/// unless [force] is set. Returns whether generation may proceed.
bool _checkFlutterIntlConflicts(
  String rootPath,
  L10nConfig config,
  Logger logger,
  bool force,
  void Function(String) warn,
) {
  final intl = PubspecReader(rootPath).readFlutterIntlConfig();
  if (intl == null) return true;

  final ours = p.normalize(config.outputDir);
  final theirs = p.normalize(intl.outputDir);

  // One directory inside the other is fine: Flutter Intl writes only
  // `l10n.dart` and `intl/messages_*.dart` at its root, which our files do not
  // share unless the two directories are the same. The VS Code extension asks
  // about nesting too; a CLI that refused would block every project using
  // both tools' defaults (lib/generated and lib/generated/modular_l10n).
  if (ours != theirs &&
      (p.isWithin(theirs, ours) || p.isWithin(ours, theirs))) {
    logger.verbose(
        'Output directory "$ours" is nested with Flutter Intl\'s "$theirs".');
  }

  final problems = <String>[
    if (config.className == intl.className)
      'Class name "${config.className}" is the same as Flutter Intl\'s, which will not compile. '
          'Set modular_l10n.class_name to something else (for example ML).',
    if (ours == theirs)
      'Output directory "$ours" is the same as Flutter Intl\'s, so both tools would write '
          'l10n.dart there. Set modular_l10n.output_dir (for example lib/generated/modular_l10n).',
  ];
  if (problems.isEmpty) return true;

  if (force) {
    problems.forEach(warn);
    return true;
  }
  for (final problem in problems) {
    logger.error(problem);
  }
  logger.error('Use --force to generate anyway.');
  return false;
}
