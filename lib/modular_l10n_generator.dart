/// Generates a type-safe, modular Flutter localization API from ARB files.
///
/// Most projects use the command line or the terminal GUI:
///
/// ```sh
/// dart run modular_l10n_generator          # generate once
/// dart run modular_l10n_generator watch    # regenerate on change
/// dart run modular_l10n_generator gui      # everything, interactively
/// ```
///
/// This library exposes the same operations for build scripts and tools.
/// It does not include the GUI, so it pulls in no terminal UI code.
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
export 'src/ops/check_ops.dart' show Issue, IssueSeverity, checkProject;
export 'src/ops/doctor_ops.dart' show DoctorItem, DoctorStatus, diagnoseProject;
export 'src/ops/exchange_ops.dart'
    show
        ExchangeFormat,
        ImportResult,
        exportTranslations,
        findFlutterIntlArbs,
        generatePseudoLocale,
        importTranslations,
        migrateFromFlutterIntl;
export 'src/ops/key_ops.dart'
    show PlaceholderSpec, addKey, moduleKeys, setTranslation, untranslatedKeys;
export 'src/ops/locale_ops.dart' show addLocale, removeLocale;
export 'src/ops/maintenance_ops.dart'
    show findUnusedKeys, removeKeys, renameKey, sortArbFiles;
export 'src/ops/module_ops.dart' show createModule, initProject;
export 'src/ops/project.dart' show OpException, OpResult, Project;
export 'src/ops/scan_ops.dart'
    show HardcodedString, extractString, planExtract, scanHardcodedStrings;
export 'src/version.dart' show packageVersion;
export 'src/watch.dart' show ArbWatcher;
