/// Generates a type-safe, modular Flutter localization API from ARB files.
///
/// Most projects use the command line:
///
/// ```sh
/// dart run modular_l10n_generator          # generate once
/// dart run modular_l10n_generator watch    # regenerate on change
/// ```
///
/// This library exposes the same pipeline for build scripts and tools.
library;

export 'src/arb_parser.dart'
    show ArbParser, ParsedModule, PlaceholderInfo, TranslationKey;
export 'src/config.dart'
    show
        ConfigOverrides,
        L10nConfig,
        LogLevel,
        ModuleAccess,
        PubspecException,
        PubspecReader,
        findProjectRoot,
        normalizeLocale;
export 'src/dart_generator.dart' show DartGenerator, GeneratorConfig;
export 'src/generate.dart' show GenerationResult, loadConfig, runGeneration;
export 'src/icu/icu_parser.dart'
    show
        ArgRole,
        IcuArg,
        IcuArgRef,
        IcuHash,
        IcuInvalid,
        IcuNode,
        IcuParseError,
        IcuParseResult,
        IcuPlural,
        IcuSelect,
        IcuText,
        collectArgs,
        parseIcu;
export 'src/logger.dart' show Logger;
export 'src/module_scanner.dart'
    show ArbFile, Module, ModuleScanner, ScanResult;
export 'src/version.dart' show packageVersion;
export 'src/watch.dart' show ArbWatcher;
