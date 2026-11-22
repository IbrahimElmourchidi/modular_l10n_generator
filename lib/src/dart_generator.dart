/// Turns parsed modules into the generated Dart API: the entry-point class,
/// one class per module, the delegate, per-locale message tables, the
/// ordinal resolver when needed, combined ARB files, and a barrel file.
///
/// The output is byte-for-byte the same as the VS Code extension's, so a team
/// can mix the two tools without the generated files churning.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'arb_parser.dart';
import 'config.dart';
import 'icu/icu_parser.dart';
import 'icu/icu_types.dart';
import 'json_writer.dart';
import 'ordinals/ordinal_codegen.dart';

/// Settings for one generation run.
class GeneratorConfig {
  const GeneratorConfig({
    required this.outputPath,
    required this.className,
    required this.defaultLocale,
    required this.supportedLocales,
    this.generateCombinedArb = true,
    this.useDeferredLoading = false,
    this.moduleAccess = ModuleAccess.part,
    this.onWarning,
    this.today,
  });

  /// Absolute output directory.
  final String outputPath;
  final String className;
  final String defaultLocale;
  final List<String> supportedLocales;
  final bool generateCombinedArb;
  final bool useDeferredLoading;
  final ModuleAccess moduleAccess;

  /// Sink for non-fatal generation warnings (bad ICU syntax, etc.).
  final void Function(String message)? onWarning;

  /// The date stamped into combined ARB files. Defaults to today (UTC).
  final DateTime? today;
}

/// What the renderer needs to know about the call site.
class _RenderContext {
  const _RenderContext({
    required this.names,
    required this.alias,
    required this.ordinalLocale,
    this.hashExpr,
  });

  /// Names the generated method accepts. Anything else stays literal.
  final Set<String> names;

  /// Placeholder name -> the local holding its formatted value.
  final Map<String, String> alias;

  /// Dart expression standing for the enclosing plural's `#`; `null` outside
  /// a plural, where `#` is ordinary text.
  final String? hashExpr;

  /// The locale of the text being rendered, as a Dart string literal. Ordinal
  /// rules follow the text, not the runtime locale.
  final String ordinalLocale;

  _RenderContext withHash(String hash) => _RenderContext(
        names: names,
        alias: alias,
        ordinalLocale: ordinalLocale,
        hashExpr: hash,
      );
}

/// One key/locale pair on its way into a generated message lookup table.
class _MessageEntry {
  const _MessageEntry({
    required this.key,
    required this.value,
    required this.textLocale,
    required this.params,
    required this.locale,
    required this.translationKey,
  });

  /// Fully qualified lookup name, e.g. `home_itemCount`.
  final String key;

  /// This locale's translation, or the template's when it has none.
  final String value;

  /// The locale [value] actually belongs to.
  final String textLocale;

  /// Canonical parameter names, from the default locale.
  final List<String> params;
  final String locale;
  final TranslationKey translationKey;
}

typedef _FormattingLine = ({
  String placeholder,
  String varDeclaration,
  String formattedVar
});

const _generatedIgnores =
    '// ignore_for_file: non_constant_identifier_names, unnecessary_string_interpolations,\n'
    '// ignore_for_file: unnecessary_string_escapes, unnecessary_brace_in_string_interps,\n'
    '// ignore_for_file: implementation_imports, library_prefixes, unused_import, prefer_single_quotes';

final _camelBoundary = RegExp(r'([a-z])([A-Z])');
final _dashOrSpace = RegExp(r'[-\s]');
final _identifierChar = RegExp(r'[A-Za-z0-9_]');
final _scriptSubtag = RegExp(r'^[A-Z][a-z]{3}$');

/// File-name form of a class or module name: `MyModule` -> `my_module`.
String toSnakeCaseName(String str) => str
    .replaceAllMapped(_camelBoundary, (m) => '${m[1]}_${m[2]}')
    .replaceAll(_dashOrSpace, '_')
    .toLowerCase();

/// `user_profile` -> `UserProfile`.
String toPascalCase(String str) => str
    .split(RegExp('[_-]'))
    .map((w) =>
        w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join();

/// `user_profile` -> `userProfile`: the module's field name on the entry point.
String toCamelCase(String str) {
  final pascal = toPascalCase(str);
  return pascal.isEmpty ? '' : pascal[0].toLowerCase() + pascal.substring(1);
}

/// Escape a run of **literal** text for a single-quoted Dart string. Never
/// apply this to synthesized interpolation.
String _escapeDartString(String str) => str
    .replaceAll(r'\', r'\\')
    .replaceAll("'", r"\'")
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\r')
    .replaceAll('\t', r'\t')
    .replaceAll(r'$', r'\$');

String _escapeForDartDoc(String str) {
  final escaped =
      str.replaceAll('`', "'").replaceAll('\n', ' ').replaceAll('\r', ' ');
  return escaped.length > 200 ? escaped.substring(0, 200) : escaped;
}

class DartGenerator {
  DartGenerator(this.config);

  final GeneratorConfig config;

  /// Warnings already emitted, so a message rendered for several locales is
  /// reported once.
  final Set<String> _warned = {};

  String get _className => config.className;

  void _warnOnce(String id, String message) {
    if (_warned.add(id)) config.onWarning?.call(message);
  }

  /// Generate every file for [modules]. Files whose content is unchanged are
  /// not rewritten. Returns the paths that were written.
  List<String> generate(List<ParsedModule> modules) {
    _written.clear();
    Directory(config.outputPath).createSync(recursive: true);

    _generateMainClass(modules);
    for (final module in modules) {
      _generateModuleClass(module);
    }
    _generateDelegate();
    _generateMessagesFiles(modules);
    _generateOrdinalHelper(modules);
    if (config.generateCombinedArb) _generateCombinedArbFiles(modules);
    _generateBarrelFile(modules);

    return List.unmodifiable(_written);
  }

  final List<String> _written = [];

  // ─── Entry point ──────────────────────────────────────────────────────

  void _generateMainClass(List<ParsedModule> modules) {
    final asParts = config.moduleAccess == ModuleAccess.part;

    final relativeImports = [
      "import 'app_localization_delegate.dart';",
      "import 'intl/modular_messages_all.dart';",
      if (_needsOrdinalHelper(modules)) "import 'intl/modular_ordinal.dart';",
      if (!asParts)
        for (final m in modules)
          "import '${toSnakeCaseName(m.name)}_l10n.dart';",
    ]..sort();

    final moduleDirectives = asParts
        ? [
            '',
            '',
            ...[
              for (final m in modules)
                "part '${toSnakeCaseName(m.name)}_l10n.dart';"
            ]..sort(),
          ].join('\n')
        : '';

    final moduleGetters = modules.map((m) {
      final className = '${toPascalCase(m.name)}L10n';
      final fieldName = toCamelCase(m.name);
      return '  $className get $fieldName => _$fieldName!;\n'
          '  static $className? _$fieldName;';
    }).join('\n');

    final moduleLoaders = modules.map((m) {
      final className = '${toPascalCase(m.name)}L10n';
      final fieldName = toCamelCase(m.name);
      return '    _$fieldName = $className.load(localeName);';
    }).join('\n');

    final c = _className;
    final content = '''// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated by Modular Flutter L10n Extension
$_generatedIgnores
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

${relativeImports.join('\n')}$moduleDirectives

/// Main Modular Localization class providing access to all module translations.
///
/// In widgets (registers dependency — auto-rebuilds on locale change):
/// ```dart
/// Text($c.of(context).auth.email)
/// Text($c.of(context).home.welcomeMessage)
/// ```
///
/// In non-widget code (services, cubits, etc.):
/// ```dart
/// final title = $c.current.auth.email;
/// ```
///
/// ## One active locale at a time
///
/// Module accessors resolve against static state set by the most recent
/// [load], and message lookup goes through `Intl.defaultLocale`, which is
/// global. That is the right model for an app that switches locale wholesale.
///
/// It does **not** support rendering two locales simultaneously — a
/// side-by-side comparison view, or an RTL preview pane inside an LTR app.
/// Nested `Localizations` scopes with different locales will all read the
/// locale that loaded last.
class $c {
  $c._();

  static $c? _current;

  static $c get current {
    assert(
      _current != null,
      'No instance of $c was loaded. '
      'Try to initialize the $c delegate before accessing $c.current.',
    );
    return _current!;
  }

$moduleGetters

  static const AppLocalizationDelegate delegate = AppLocalizationDelegate();

  static Future<$c> load(Locale locale) async {
    final name = (locale.countryCode?.isEmpty ?? false)
        ? locale.languageCode
        : locale.toString();
    final localeName = Intl.canonicalizedLocale(name);
    Intl.defaultLocale = localeName;

    // Register message lookup tables for the locale
    await initializeModularMessages(localeName);

    final instance = $c._();
    $c._current = instance;

    // Load all module translations
$moduleLoaders

    return instance;
  }

  static $c of(BuildContext context) {
    final instance = $c.maybeOf(context);
    assert(
      instance != null,
      'No instance of $c present in the widget tree. '
      'Did you add $c.delegate in localizationsDelegates?',
    );
    return instance!;
  }

  static $c? maybeOf(BuildContext context) {
    return Localizations.of<$c>(context, $c);
  }

  /// List of all supported locales
  static const List<Locale> supportedLocales = [
${config.supportedLocales.map(_localeConstructor).join(',\n')}
  ];
}
''';

    _writeIfChanged(
        p.join(config.outputPath, '${toSnakeCaseName(c)}.dart'), content);
  }

  /// A `Locale` constructor for `en`, `en_US`, `zh_Hans` or `zh_Hans_CN`.
  String _localeConstructor(String locale) {
    final parts = locale.replaceAll('-', '_').split('_');

    switch (parts.length) {
      case 1:
        return "    Locale('${parts[0]}')";
      case 2:
        final [lang, second] = parts;
        return _scriptSubtag.hasMatch(second)
            ? "    Locale.fromSubtags(languageCode: '$lang', scriptCode: '$second')"
            : "    Locale('$lang', '$second')";
      case 3:
        final [lang, script, region] = parts;
        return "    Locale.fromSubtags(languageCode: '$lang', scriptCode: '$script', countryCode: '$region')";
    }

    _warnOnce(
      'locale-shape:$locale',
      'Locale "$locale" is not in language[_Script][_REGION] form; '
          "falling back to Locale('$locale')",
    );
    return "    Locale('$locale')";
  }

  // ─── Module classes ───────────────────────────────────────────────────

  void _generateModuleClass(ParsedModule module) {
    final className = '${toPascalCase(module.name)}L10n';
    final methods =
        module.keys.map((k) => _generateMethod(k, module.name)).join('\n\n');

    // A part file cannot have imports; it shares the entry point's.
    final needsOrdinal = module.keys.any(_keyUsesOrdinal);
    final directives = config.moduleAccess == ModuleAccess.part
        ? "part of '${toSnakeCaseName(_className)}.dart';"
        : [
            "import 'package:intl/intl.dart';",
            if (needsOrdinal) "import 'intl/modular_ordinal.dart';",
          ].join('\n');

    final content = '''// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated by Modular Flutter L10n Extension
// Module: ${module.name}
$_generatedIgnores
$directives

/// Localization class for the ${module.name} module.
class $className {
  $className._();

  static $className? _instance;

  static $className load(String localeName) {
    _instance = $className._();
    return _instance!;
  }

  static $className get instance {
    assert(_instance != null, '$className not loaded');
    return _instance!;
  }

$methods
}
''';

    _writeIfChanged(
      p.join(config.outputPath, '${toSnakeCaseName(module.name)}_l10n.dart'),
      content,
    );
  }

  /// Render one ARB message as a Dart getter or method. One renderer handles
  /// every shape: plain text, plural, select, or any nesting of them.
  String _generateMethod(TranslationKey key, String moduleName) {
    final translation = _nonEmpty(key.translations[config.defaultLocale]) ?? '';
    final parsed = parseIcu(translation);
    final nodes = parsed.nodes;
    final lookupName = '${moduleName}_${key.key}';

    for (final (i, error) in parsed.errors.indexed) {
      _warnOnce('$lookupName:parse:${error.start}:$i',
          '$moduleName.${key.key}: ${error.message}');
    }

    // Derived once, from the template locale, and reused by every locale's
    // lookup entry: intl binds arguments positionally.
    final args = ArbParser.getArguments(translation);
    final orderedParams = _orderParams(args, key.placeholders);

    final description = _nonEmpty(key.description) ?? translation;
    final escapedDescription = _escapeForDartDoc(description);
    final desc = _escapeDartString(key.description ?? '');

    // Nothing to substitute: keep the getter form.
    if (orderedParams.isEmpty &&
        !nodes.any((n) => n is IcuPlural || n is IcuSelect)) {
      final literal = _toDartLiteral(
        nodes,
        _RenderContext(
            names: const {},
            alias: const {},
            ordinalLocale: _defaultLocaleLiteral),
      );
      return '''  /// $escapedDescription
  String get ${key.key} {
    return Intl.message(
      $literal,
      name: '$lookupName',
      desc: '$desc',
      args: [],
    );
  }''';
    }

    // Placeholders carrying NumberFormat / DateFormat metadata are formatted
    // into a local first; the message interpolates the formatted value.
    final formattingLines = _formattingLines(key, orderedParams, args);
    final alias = {
      for (final f in formattingLines) f.placeholder: f.formattedVar
    };
    final params = orderedParams
        .map((name) => '${_dartType(key, name, args)} $name')
        .join(', ');
    final formattedVars = formattingLines.isEmpty
        ? ''
        : '${formattingLines.map((f) => f.varDeclaration).join('\n    ')}\n    ';

    // The string handed to Intl.message is the runtime fallback, so it has to
    // be real Dart interpolation, not the raw ARB text.
    final message = _toDartLiteral(
      nodes,
      _RenderContext(
        names: orderedParams.toSet(),
        alias: alias,
        ordinalLocale: _defaultLocaleLiteral,
      ),
    );

    // `args:` decides what the lookup closure is called with: an operand
    // arrives raw (it feeds Intl.plural), a plain placeholder formatted.
    final lookupArgs = orderedParams
        .map((name) => _isOperand(args, name) ? name : alias[name] ?? name);

    return '''  /// $escapedDescription
  String ${key.key}($params) {
    ${formattedVars}return Intl.message(
      $message,
      name: '$lookupName',
      desc: '$desc',
      args: [${lookupArgs.join(', ')}],
    );
  }''';
  }

  static bool _isOperand(List<IcuArg> args, String name) {
    for (final arg in args) {
      if (arg.name == name) {
        return arg.role == ArgRole.pluralOperand ||
            arg.role == ArgRole.ordinalOperand;
      }
    }
    return false;
  }

  /// Order the arguments with the same rule the lookup entries use.
  static List<String> _orderParams(
      List<IcuArg> args, Map<String, PlaceholderInfo>? metadata) {
    final text = args.map((a) => '{${a.name}}').join(' ');
    return ArbParser.getOrderedPlaceholders(text, metadata);
  }

  String _dartType(TranslationKey key, String name, List<IcuArg> args) =>
      resolvePlaceholderDartType(key.placeholders?[name]?.type, name, args);

  // ─── Rendering ────────────────────────────────────────────────────────

  String _toDartLiteral(List<IcuNode> nodes, _RenderContext ctx) =>
      "'${_renderNodes(nodes, ctx)}'";

  /// Render a parsed message into the *body* of a single-quoted Dart string.
  String _renderNodes(List<IcuNode> nodes, _RenderContext ctx) {
    final out = StringBuffer();

    for (var i = 0; i < nodes.length; i++) {
      switch (nodes[i]) {
        case IcuText(:final value):
          out.write(_escapeDartString(value));
        case IcuArgRef(:final name):
          // Only names the caller supplies become interpolations.
          if (!ctx.names.contains(name)) {
            out.write('{$name}');
            break;
          }
          out.write(
              _interpolate(ctx.alias[name] ?? name, _followingChar(nodes, i)));
        case IcuHash():
          out.write(ctx.hashExpr == null ? '#' : '\${${ctx.hashExpr}}');
        case final IcuSelect node:
          out.write('\${${_renderSelect(node, ctx)}}');
        case final IcuPlural node:
          out.write('\${${_renderPlural(node, ctx)}}');
        case IcuInvalid(:final raw):
          out.write(_escapeDartString(raw));
      }
    }

    return out.toString();
  }

  /// The character that follows an interpolation, if any.
  static String _followingChar(List<IcuNode> nodes, int index) {
    if (index + 1 >= nodes.length) return '';
    final next = nodes[index + 1];
    return next is IcuText && next.value.isNotEmpty ? next.value[0] : '';
  }

  /// `$name`, or `${name}` when the next character could extend it.
  static String _interpolate(String name, String following) =>
      following.isNotEmpty && _identifierChar.hasMatch(following)
          ? '\${$name}'
          : '\$$name';

  String _renderSelect(IcuSelect node, _RenderContext ctx) {
    final cases = Map.of(node.cases);
    _synthesizeOther(cases, node.name);

    final entries = cases.entries.map((e) =>
        "'${_escapeDartString(e.key)}': '${_renderNodes(e.value, ctx)}'");
    return 'Intl.select(${ctx.alias[node.name] ?? node.name}, {${entries.join(', ')}})';
  }

  String _renderPlural(IcuPlural node, _RenderContext ctx) {
    // The raw parameter, never the formatting alias: Intl.plural needs a num.
    final operand = node.name;
    final shifted = node.offset != 0 ? '$operand - ${node.offset}' : operand;
    final inner = ctx.withHash(shifted);

    final branches = _pluralBranches(node, inner, asMapKeys: node.ordinal);
    var expr = node.ordinal
        ? 'modularOrdinalBranch(modularOrdinalCategory(${ctx.ordinalLocale}, $shifted), {$branches})'
        : 'Intl.plural($shifted, $branches)';

    // Exact selectors test the *raw* value, outside Intl.plural.
    for (final selector in node.exactSelectors) {
      final body = node.cases[selector];
      if (body == null) continue;
      expr =
          "$operand == ${selector.substring(1)} ? '${_renderNodes(body, inner)}' : $expr";
    }

    return expr;
  }

  String _ordinalLocaleLiteral(String locale) =>
      "'${_escapeDartString(locale.replaceAll('-', '_'))}'";

  String get _defaultLocaleLiteral =>
      _ordinalLocaleLiteral(config.defaultLocale);

  /// The case list for a plural or ordinal block, in CLDR category order.
  String _pluralBranches(IcuPlural node, _RenderContext ctx,
      {required bool asMapKeys}) {
    final categories = <String, List<IcuNode>>{
      for (final e in node.cases.entries)
        if (!e.key.startsWith('=')) e.key: e.value,
    };
    _synthesizeOther(categories, node.name);

    return ['zero', 'one', 'two', 'few', 'many', 'other']
        .where(categories.containsKey)
        .map((key) {
      final name = asMapKeys ? "'$key'" : key;
      return "$name: '${_renderNodes(categories[key]!, ctx)}'";
    }).join(', ');
  }

  /// Guarantee an `other` branch: it is a required parameter of
  /// `Intl.plural` and `Intl.select`.
  void _synthesizeOther(Map<String, List<IcuNode>> cases, String name) {
    if (cases.containsKey('other')) return;

    final first = cases.keys.isEmpty ? null : cases.keys.first;
    _warnOnce(
      'synthesize-other:$name:${first ?? ''}',
      'Missing "other" case for "$name"; falling back to '
          '${first == null ? 'an empty message' : '"$first"'}',
    );
    cases['other'] = first == null ? const [] : cases[first]!;
  }

  /// Locals that format placeholders carrying `NumberFormat` / `DateFormat`
  /// metadata.
  List<_FormattingLine> _formattingLines(
    TranslationKey key,
    List<String> placeholders,
    List<IcuArg> args,
  ) {
    final lines = <_FormattingLine>[];
    final metadata = key.placeholders;
    if (metadata == null) return lines;

    for (final name in placeholders) {
      final meta = metadata[name];
      final format = meta?.format;
      if (meta == null || format == null || format.isEmpty) continue;

      // An operand is passed to Intl.plural raw, and `#` substitutes it
      // unformatted, so it gets no formatted local.
      if (_isOperand(args, name)) {
        _warnOnce(
          'operand-format:${key.key}:$name',
          '${key.key}: "{$name}" is a plural operand, so its "$format" format is '
              'ignored — the value is passed to `Intl.plural` raw, and `#` '
              'substitutes it unformatted.',
        );
        continue;
      }

      final formattedVar = '${name}String';

      if (meta.type == 'DateTime') {
        final declaration = meta.isCustomDateFormat == 'true'
            ? "final $formattedVar = DateFormat('${_escapeDartString(format)}').format($name);"
            : 'final $formattedVar = DateFormat.$format().format($name);';
        lines.add((
          placeholder: name,
          varDeclaration: declaration,
          formattedVar: formattedVar
        ));
      } else if (meta.type == 'int' ||
          meta.type == 'double' ||
          meta.type == 'num') {
        final optional = meta.optionalParameters;
        final entries = optional == null
            ? ''
            : optional.entries
                .map((e) => e.value is num
                    ? '${e.key}: ${jsString(e.value)}'
                    : "${e.key}: '${_escapeDartString(e.value as String)}'")
                .join(', ');
        lines.add((
          placeholder: name,
          varDeclaration:
              'final $formattedVar = NumberFormat.$format($entries).format($name);',
          formattedVar: formattedVar,
        ));
      }
    }

    return lines;
  }

  // ─── Delegate ─────────────────────────────────────────────────────────

  void _generateDelegate() {
    final c = _className;
    final content = '''// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated by Modular Flutter L10n Extension
$_generatedIgnores
import 'package:flutter/material.dart';
import '${toSnakeCaseName(c)}.dart';

class AppLocalizationDelegate extends LocalizationsDelegate<$c> {
  const AppLocalizationDelegate();

  @override
  bool isSupported(Locale locale) => _resolve(locale) != null;

  @override
  Future<$c> load(Locale locale) =>
      $c.load(_resolve(locale) ?? locale);

  /// Narrow [locale] to the closest supported locale.
  ///
  /// Matching a device locale on language alone (so `en_GB` satisfies a project
  /// that only ships `en_US`) is right, but the *device* locale must not then be
  /// handed to load() — no message table is registered under it. Resolve to the
  /// supported locale first: exact match, then language+country, then language.
  static Locale? _resolve(Locale locale) {
    for (final supported in $c.supportedLocales) {
      if (supported == locale) return supported;
    }
    for (final supported in $c.supportedLocales) {
      if (supported.languageCode == locale.languageCode &&
          supported.countryCode == locale.countryCode) {
        return supported;
      }
    }
    for (final supported in $c.supportedLocales) {
      if (supported.languageCode == locale.languageCode) return supported;
    }
    return null;
  }

  @override
  bool shouldReload(AppLocalizationDelegate old) => false;
}
''';

    _writeIfChanged(
        p.join(config.outputPath, 'app_localization_delegate.dart'), content);
  }

  // ─── Message tables ───────────────────────────────────────────────────

  /// Whether a locale carries text of its own for a key. The empty string,
  /// which the extension writes as a placeholder for new locales, does not.
  static bool _hasOwnTranslation(TranslationKey key, String locale) =>
      (key.translations[locale] ?? '').isNotEmpty;

  /// The text a locale renders for a key, falling back to the template.
  String _translationText(TranslationKey key, String locale) =>
      _hasOwnTranslation(key, locale)
          ? key.translations[locale]!
          : key.translations[config.defaultLocale] ?? '';

  void _generateMessagesFiles(List<ParsedModule> modules) {
    final messagesDir = p.join(config.outputPath, 'intl');
    Directory(messagesDir).createSync(recursive: true);

    for (final locale in config.supportedLocales) {
      final messages = <_MessageEntry>[
        for (final module in modules)
          for (final key in module.keys)
            _MessageEntry(
              key: '${module.name}_${key.key}',
              value: _translationText(key, locale),
              textLocale: _hasOwnTranslation(key, locale)
                  ? locale
                  : config.defaultLocale,
              params: ArbParser.getOrderedPlaceholders(
                key.translations[config.defaultLocale] ?? '',
                key.placeholders,
              ),
              locale: locale,
              translationKey: key,
            ),
      ];

      _writeIfChanged(
        p.join(messagesDir, 'modular_messages_$locale.dart'),
        _messagesFileContent(locale, messages),
      );
    }

    _generateMessagesAll();
  }

  /// One locale's lookup table. Entries must not pass `name:` / `args:` to
  /// `Intl.plural` / `Intl.select`: the lookup would resolve back to the same
  /// closure and recurse until the stack overflows.
  String _messagesFileContent(String locale, List<_MessageEntry> messages) {
    // Imports follow the text actually rendered, which is the template's
    // whenever a translation cannot be rendered with the canonical arguments.
    final rendered = messages
        .map((entry) => (entry: entry, rendered: _renderedLookupEntry(entry)))
        .toList();

    final messageEntries = rendered
        .map((r) =>
            _renderLookupEntry(r.entry, r.rendered.text, r.rendered.locale))
        .join('\n');

    final usesIntl = rendered.any((r) => _needsIntl(r.rendered.text));
    final usesOrdinal = rendered.any((r) => _textUsesOrdinal(r.rendered.text));

    final importBlock = [
      if (usesIntl) 'package:intl/intl.dart',
      'package:intl/message_lookup_by_library.dart',
      if (usesOrdinal) 'modular_ordinal.dart',
    ].map((uri) => "import '$uri';").join('\n');

    return '''// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated by Modular Flutter L10n Extension
$_generatedIgnores
$importBlock

final messages = ModularMessageLookup();

class ModularMessageLookup extends MessageLookupByLibrary {
  @override
  String get localeName => '$locale';

  @override
  final messages = <String, Function>{
$messageEntries
  };
}
''';
  }

  static bool _needsIntl(String text) => containsIcuNode(
      parseIcu(text).nodes, (n) => n is IcuPlural || n is IcuSelect);

  static bool _textUsesOrdinal(String text) =>
      containsIcuNode(parseIcu(text).nodes, (n) => n is IcuPlural && n.ordinal);

  bool _keyUsesOrdinal(TranslationKey key) =>
      _textUsesOrdinal(key.translations[config.defaultLocale] ?? '');

  /// Whether any locale's text needs the ordinal resolver. An
  /// over-approximation costs an unused helper; missing one is a compile error.
  bool _needsOrdinalHelper(List<ParsedModule> modules) => modules.any(
      (m) => m.keys.any((k) => k.translations.values.any(_textUsesOrdinal)));

  String _renderLookupEntry(
      _MessageEntry entry, String renderedText, String renderedLocale) {
    final canonical = entry.params;

    // Fall back to the template only when this locale's message cannot be
    // satisfied by the canonical arguments; either reason fails to compile.
    final fallback = _lookupFallbackReason(entry);
    if (fallback != null) {
      _warnOnce(
        'lookup-fallback:${entry.locale}:${entry.key}',
        '[${entry.locale}] ${entry.key}: $fallback; using the '
            '${config.defaultLocale} translation instead',
      );
      return _renderStaticLookupEntry(entry, renderedText);
    }

    final body = _renderNodes(
      parseIcu(renderedText).nodes,
      _RenderContext(
        names: canonical.toSet(),
        alias: const {},
        ordinalLocale: _ordinalLocaleLiteral(renderedLocale),
      ),
    );

    if (canonical.isEmpty && !_needsIntl(renderedText)) {
      return "    '${entry.key}': MessageLookupByLibrary.simpleMessage('$body'),";
    }
    return "    '${entry.key}': (${canonical.join(', ')}) => '$body',";
  }

  /// The text a lookup entry renders, and the locale that text belongs to.
  ({String text, String locale}) _renderedLookupEntry(_MessageEntry entry) {
    if (_lookupFallbackReason(entry) != null) {
      return (
        text: entry.translationKey.translations[config.defaultLocale] ?? '',
        locale: config.defaultLocale,
      );
    }
    return (text: entry.value, locale: entry.textLocale);
  }

  String _renderStaticLookupEntry(_MessageEntry entry, String text) {
    final body = _renderNodes(
      parseIcu(text).nodes,
      _RenderContext(
        names: entry.params.toSet(),
        alias: const {},
        ordinalLocale: _defaultLocaleLiteral,
      ),
    );
    return "    '${entry.key}': (${entry.params.join(', ')}) => '$body',";
  }

  /// The template's arguments with the Dart types the module method gives
  /// them, warning once per declared type a role had to overrule.
  List<CanonicalArg> _canonicalArgs(TranslationKey key) {
    final args =
        ArbParser.getArguments(key.translations[config.defaultLocale] ?? '');
    final canonical =
        buildCanonicalArgs(args, (name) => key.placeholders?[name]?.type);

    for (final arg in canonical) {
      final declared = key.placeholders?[arg.name]?.type;
      if (declared == null || declared.isEmpty || declared == arg.dartType) {
        continue;
      }
      final role = args.where((a) => a.name == arg.name).firstOrNull?.role;
      if (role != null && checkRoleCompatibility(declared, role) != null) {
        _warnOnce(
          'placeholder-type:${arg.name}:$declared:${arg.dartType}',
          '"@${arg.name}" is declared as "$declared" but is used as a '
              'plural operand, so it is typed "${arg.dartType}"',
        );
      }
    }
    return canonical;
  }

  String? _lookupFallbackReason(_MessageEntry entry) => firstIncompatibleArg(
        _canonicalArgs(entry.translationKey),
        ArbParser.getArguments(entry.value),
      )?.reason;

  void _generateMessagesAll() {
    final locales = config.supportedLocales;
    String alias(String l) => 'modular_messages_${l.replaceAll('-', '_')}';

    final imports = ([
      for (final l in locales)
        config.useDeferredLoading
            ? "import 'modular_messages_$l.dart' deferred as ${alias(l)};"
            : "import 'modular_messages_$l.dart' as ${alias(l)};",
    ]..sort())
        .join('\n');

    final libraries = locales
        .map((l) => config.useDeferredLoading
            ? "  '$l': () => ${alias(l)}.loadLibrary(),"
            : "  '$l': () => Future.value(null),")
        .join('\n');

    final cases = locales
        .map((l) => "    case '$l':\n      return ${alias(l)}.messages;")
        .join('\n');

    final content = '''// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated by Modular Flutter L10n Extension
$_generatedIgnores
import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';
import 'package:intl/src/intl_helpers.dart';

$imports

typedef LibraryLoader = Future<dynamic> Function();

Map<String, LibraryLoader> _deferredLibraries = {
$libraries
};

MessageLookupByLibrary? _findExact(String localeName) {
  switch (localeName) {
$cases
    default:
      return null;
  }
}

MessageLookupByLibrary? _findGeneratedMessagesFor(String locale) {
  final actualLocale = Intl.verifiedLocale(
    locale,
    (locale) => _deferredLibraries[locale] != null,
    onFailure: (_) => null,
  );
  if (actualLocale == null) return null;
  return _findExact(actualLocale);
}

/// Initialize modular localization messages.
/// Named differently from Flutter Intl's initializeMessages to avoid conflicts.
Future<bool> initializeModularMessages(String localeName) async {
  final availableLocale = Intl.verifiedLocale(
    localeName,
    (locale) => _deferredLibraries[locale] != null,
    onFailure: (_) => null,
  );
  if (availableLocale == null) {
    return false;
  }
  final lib = _deferredLibraries[availableLocale];
  await lib?.call();
  initializeInternalMessageLookup(CompositeMessageLookup.new);
  messageLookup.addLocale(availableLocale, _findGeneratedMessagesFor);
  return true;
}
''';

    _writeIfChanged(
        p.join(config.outputPath, 'intl', 'modular_messages_all.dart'),
        content);
  }

  // ─── Combined ARB, barrel, ordinals ───────────────────────────────────

  void _generateCombinedArbFiles(List<ParsedModule> modules) {
    final arbDir = p.join(config.outputPath, 'arb');
    Directory(arbDir).createSync(recursive: true);

    // Date only: a full timestamp would rewrite these files on every run.
    final today = (config.today ?? DateTime.now())
        .toUtc()
        .toIso8601String()
        .split('T')
        .first;

    for (final locale in config.supportedLocales) {
      final combined = <String, Object?>{
        '@@locale': locale,
        '@@last_modified': today
      };

      for (final module in modules) {
        for (final key in module.keys) {
          final fullKey = '${module.name}_${key.key}';
          combined[fullKey] = _translationText(key, locale);

          if ((key.description ?? '').isNotEmpty || key.placeholders != null) {
            combined['@$fullKey'] = {
              if (key.description != null) 'description': key.description,
              if (key.placeholders != null)
                'placeholders': {
                  for (final e in key.placeholders!.entries)
                    e.key: e.value.toJson(),
                },
            };
          }
        }
      }

      _writeIfChanged(p.join(arbDir, 'modular_l10n_$locale.arb'),
          encodeJsonLikeJs(combined));
    }
  }

  void _generateBarrelFile(List<ParsedModule> modules) {
    final exports = [
      "export '${toSnakeCaseName(_className)}.dart';",
      "export 'app_localization_delegate.dart';",
      if (config.moduleAccess != ModuleAccess.part)
        for (final m in modules)
          "export '${toSnakeCaseName(m.name)}_l10n.dart';",
    ]..sort();

    final content = '''// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated by Modular Flutter L10n Extension
$_generatedIgnores
${exports.join('\n')}
''';

    _writeIfChanged(p.join(config.outputPath, 'l10n.dart'), content);
  }

  /// Write `intl/modular_ordinal.dart` when any message uses `selectordinal`.
  void _generateOrdinalHelper(List<ParsedModule> modules) {
    final locales = <String>{
      for (final module in modules)
        for (final key in module.keys)
          for (final locale in config.supportedLocales)
            if (_textUsesOrdinal(key.translations[locale] ?? '')) locale,
    }.toList()
      ..sort();
    if (locales.isEmpty) return;

    final compiled = compileOrdinals(locales);
    for (final locale in compiled.unmapped) {
      _warnOnce(
        'ordinal-unmapped:$locale',
        'No CLDR ordinal rules for "$locale"; ordinal messages will fall back to "other"',
      );
    }

    _writeIfChanged(p.join(config.outputPath, 'intl', 'modular_ordinal.dart'),
        compiled.content);
  }

  /// Write only when the content differs, so watch mode does not churn
  /// mtimes or `git status`.
  void _writeIfChanged(String filePath, String content) {
    final file = File(filePath);
    try {
      if (file.existsSync() && file.readAsStringSync() == content) return;
    } on FileSystemException {
      // Unreadable: overwrite.
    }
    file.writeAsStringSync(content);
    _written.add(filePath);
  }

  static String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;
}
