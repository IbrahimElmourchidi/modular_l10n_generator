// Parity harness: build a project from the extension's fixture corpus, run the
// TypeScript pipeline on one copy. The Dart CLI is run on a second copy by the
// caller, and the two output trees are diffed.
//
//   Driven by tool/update_parity_goldens.sh; see there.
const fs = require('fs');
const path = require('path');

const [tsout, work, moduleAccess = 'part', deferred = 'false'] = process.argv.slice(2);
const { FIXTURES } = require(path.join(tsout, 'fixtures/icu_corpus.js'));
const { ModuleScanner } = require(path.join(tsout, 'module_scanner.js'));
const { ArbParser } = require(path.join(tsout, 'arb_parser.js'));
const { DartGenerator } = require(path.join(tsout, 'dart_generator.js'));
const { resolveEffectiveDefaultLocale } = require(path.join(tsout, 'pubspec_config.js'));

function writeJson(file, obj) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(obj, null, 2));
}

function buildProject(root) {
    fs.rmSync(root, { recursive: true, force: true });
    fs.mkdirSync(root, { recursive: true });
    fs.writeFileSync(
        path.join(root, 'pubspec.yaml'),
        `name: parity_app\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n` +
        `modular_l10n:\n  module_access: ${moduleAccess}\n  use_deferred_loading: ${deferred}\n`
    );

    // The corpus module, in five locales including a hyphenated one.
    const files = { en: {}, ar: {}, ru: {} };
    for (const f of FIXTURES) {
        for (const loc of ['en', 'ar', 'ru']) {
            if (f[loc] !== undefined) files[loc][f.key] = f[loc];
        }
        if (f.placeholders && f.en !== undefined) {
            files.en[`@${f.key}`] = { placeholders: f.placeholders };
        }
    }
    const dir = path.join(root, 'lib/features/fixture/l10n');
    for (const loc of ['en', 'ar', 'ru']) {
        writeJson(path.join(dir, `${loc}.arb`), { '@@locale': loc, '@@context': 'fixture', ...files[loc] });
    }
    writeJson(path.join(dir, 'zh_Hans.arb'), { '@@locale': 'zh-Hans', '@@context': 'fixture' });
    writeJson(path.join(dir, 'zh_Hans_CN.arb'), { '@@locale': 'zh_Hans_CN', '@@context': 'fixture' });

    // Modules whose order depends on ICU collation (auth vs auth_extra vs auth-x).
    writeJson(path.join(root, 'lib/features/auth/l10n/en.arb'), {
        '@@locale': 'en', '@@context': 'auth',
        emailLabel: 'Email',
        '@emailLabel': { description: 'Label for the `email` field\nsecond line' },
        welcome: 'Welcome back, {name}! You have {count, plural, =0{no messages} one{one message} other{# messages}}.',
        '@welcome': {
            description: '',
            placeholders: { name: { type: 'String', example: 42 }, count: { type: 'int', example: 2.0 } },
        },
        price: 'Price: {amount}',
        '@price': {
            placeholders: {
                amount: { type: 'double', format: 'currency', optionalParameters: { decimalDigits: 2.0, symbol: '€', name: 'EUR' } },
            },
        },
        due: 'Due {date}',
        '@due': { placeholders: { date: { type: 'DateTime', format: 'yMMMd' } } },
        dueCustom: 'Due {date}',
        '@dueCustom': { placeholders: { date: { type: 'DateTime', format: "EEE, MMM d ''yy", isCustomDateFormat: 'true' } } },
        dollars: 'Costs $5 \\ "quoted" and it\'s tabbed\there',
        emptyValue: '',
    });
    writeJson(path.join(root, 'lib/features/auth/l10n/ar.arb'), {
        '@@locale': 'ar', '@@context': 'auth',
        emailLabel: 'البريد',
        welcome: 'مرحبا {name}! {count, plural, zero{لا رسائل} one{رسالة} two{رسالتان} few{# رسائل} many{# رسالة} other{# رسالة}}',
        '@welcome': { description: 'ar-only description should not override' },
        price: '',
    });
    writeJson(path.join(root, 'lib/features/auth_extra/l10n/en.arb'), {
        '@@locale': 'en', '@@context': 'auth_extra', ok: 'OK', place: '{n, selectordinal, one{#st} two{#nd} few{#rd} other{#th}}',
    });
    writeJson(path.join(root, 'lib/features/Main/l10n/en.arb'), {
        '@@locale': 'en', '@@context': 'home_screen', title: 'Home', '@title': { description: 'Home title' },
    });
    writeJson(path.join(root, 'lib/features/home/l10n/ar.arb'), {
        '@@locale': 'ar', '@@context': 'home_screen', title: 'الرئيسية',
    });
    // Skipped or rejected inputs.
    writeJson(path.join(root, 'lib/l10n/intl_en.arb'), { '@@locale': 'en', title: 'flutter intl' });
    writeJson(path.join(root, 'lib/features/bad/l10n/en.arb'), { '@@locale': 'en', '@@context': 'Bad-Name' });
    writeJson(path.join(root, 'lib/features/bad/l10n/xx.arb'), { '@@locale': 'xx_YY', '@@context': 'bad' });
    fs.mkdirSync(path.join(root, 'lib/features/broken/l10n'), { recursive: true });
    fs.writeFileSync(path.join(root, 'lib/features/broken/l10n/en.arb'), '{ not json');
    writeJson(path.join(root, 'build/x/l10n/en.arb'), { '@@locale': 'en', '@@context': 'ignored' });
    writeJson(path.join(root, '.hidden/l10n/en.arb'), { '@@locale': 'en', '@@context': 'hidden' });
}

(async () => {
    const tsRoot = path.join(work, 'ts');
    buildProject(tsRoot);
    // The Dart copy is an identical tree.
    fs.rmSync(path.join(work, 'dart'), { recursive: true, force: true });
    fs.cpSync(tsRoot, path.join(work, 'dart'), { recursive: true });

    const warnings = [];
    const scanner = new ModuleScanner(tsRoot, '**/l10n/*.arb');
    const scan = await scanner.scanModules();
    for (const w of scan.warnings ?? []) warnings.push(w);
    for (const e of scan.validationErrors ?? []) warnings.push(e);
    const defaultLocale = resolveEffectiveDefaultLocale('en', scan.detectedLocales) ?? 'en';
    const parsed = await new ArbParser((m) => warnings.push(m)).parseModules(scan.modules, scan.detectedLocales, defaultLocale);
    await new DartGenerator({
        outputPath: path.join(tsRoot, 'lib/generated/modular_l10n'),
        className: 'ML',
        defaultLocale,
        supportedLocales: scan.detectedLocales,
        generateCombinedArb: true,
        useDeferredLoading: deferred === 'true',
        moduleAccess,
        onWarning: (m) => warnings.push(m),
    }).generate(parsed);
    fs.writeFileSync(path.join(work, 'ts_warnings.txt'), warnings.join('\n') + '\n');
    console.log(`TS: ${scan.modules.map((m) => m.name).join(', ')} | ${scan.detectedLocales.join(', ')} | ${warnings.length} warnings`);
})();
