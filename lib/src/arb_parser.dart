/// Reads a module's ARB files into one list of keys, each with its
/// translation per locale and its `@key` metadata.
library;

import 'icu/icu_parser.dart';
import 'module_scanner.dart';

/// One key of a module, across every locale.
class TranslationKey {
  TranslationKey(this.key, {this.description, this.placeholders});

  final String key;

  /// Locale to message text.
  final Map<String, String> translations = {};
  String? description;

  /// `@key.placeholders`, in declaration order.
  Map<String, PlaceholderInfo>? placeholders;
}

/// One entry of `@key.placeholders`.
class PlaceholderInfo {
  const PlaceholderInfo({
    this.type,
    this.example,
    this.format,
    this.isCustomDateFormat,
    this.optionalParameters,
  });

  final String? type;

  /// Stringified: hand-written ARB files sometimes carry a bare number.
  final String? example;
  final String? format;
  final String? isCustomDateFormat;

  /// Values are `String` or `num`. Numbers stay numbers so the generator can
  /// emit `decimalDigits: 2` rather than `decimalDigits: '2'`.
  final Map<String, Object>? optionalParameters;

  /// The ARB form, omitting absent fields.
  Map<String, Object?> toJson() => {
        if (type != null) 'type': type,
        if (example != null) 'example': example,
        if (format != null) 'format': format,
        if (isCustomDateFormat != null)
          'isCustomDateFormat': isCustomDateFormat,
        if (optionalParameters != null)
          'optionalParameters': optionalParameters,
      };
}

/// A module with its keys parsed.
class ParsedModule {
  const ParsedModule(this.name, this.path, this.keys);

  final String name;
  final String path;
  final List<TranslationKey> keys;
}

class ArbParser {
  /// [onWarning] receives non-fatal problems, such as an unreadable file.
  ArbParser({this.onWarning});

  final void Function(String message)? onWarning;

  List<ParsedModule> parseModules(List<Module> modules,
      {String? defaultLocale}) {
    return [
      for (final module in modules)
        ParsedModule(
            module.name, module.path, _parseModule(module, defaultLocale)),
    ];
  }

  List<TranslationKey> _parseModule(Module module, String? defaultLocale) {
    final keys = <String, TranslationKey>{};

    // The default locale is read first: `@key` metadata is authored there,
    // and a locale that sorts earlier (ar before en) would otherwise create
    // the key with no metadata.
    final ordered = defaultLocale == null
        ? module.arbFiles
        : [
            ...module.arbFiles.where((f) => f.locale == defaultLocale),
            ...module.arbFiles.where((f) => f.locale != defaultLocale),
          ];

    for (final arbFile in ordered) {
      final content = _readArbFile(arbFile.path);
      for (final MapEntry(:key, :value) in content.entries) {
        if (key.startsWith('@')) continue;

        if (value is! String) {
          onWarning?.call(
            '${arbFile.path}: "$key" is not a string and was skipped',
          );
          continue;
        }

        final metadata = content['@$key'];
        final meta = metadata is Map<String, Object?> ? metadata : null;
        final description = meta?['description'];

        final existing = keys[key];
        if (existing == null) {
          keys[key] = TranslationKey(
            key,
            description: description is String ? description : null,
            placeholders: _parsePlaceholders(meta?['placeholders']),
          );
        } else if (meta != null) {
          // A non-default locale may still carry metadata the default one
          // omitted; fill gaps without overriding what's set.
          existing.description ??= description is String ? description : null;
          existing.placeholders ??= _parsePlaceholders(meta['placeholders']);
        }

        keys[key]!.translations[arbFile.locale] = value;
      }
    }

    return keys.values.toList();
  }

  Map<String, Object?> _readArbFile(String filePath) {
    try {
      final json = readJsonFile(filePath);
      if (json is Map<String, Object?>) return json;
      onWarning?.call('Error reading ARB file $filePath: not a JSON object');
    } on Object catch (error) {
      onWarning?.call('Error reading ARB file $filePath: $error');
    }
    return const {};
  }

  static Map<String, PlaceholderInfo>? _parsePlaceholders(
      Object? placeholders) {
    if (placeholders is! Map<String, Object?>) return null;

    return {
      for (final MapEntry(:key, :value) in placeholders.entries)
        key: () {
          final info =
              value is Map<String, Object?> ? value : const <String, Object?>{};
          final example = info['example'];
          return PlaceholderInfo(
            type: _asString(info['type']),
            example: example == null ? null : jsString(example),
            format: _asString(info['format']),
            isCustomDateFormat: _asString(info['isCustomDateFormat']),
            optionalParameters: _optionalParameters(info['optionalParameters']),
          );
        }(),
    };
  }

  static String? _asString(Object? value) => value is String ? value : null;

  static Map<String, Object>? _optionalParameters(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final result = <String, Object>{
      for (final MapEntry(:key, :value) in value.entries)
        if (value is num || value is String) key: value!,
    };
    return result.isEmpty ? null : result;
  }

  // ─── ICU helpers ──────────────────────────────────────────────────────

  /// Arguments the message needs, in first-appearance order, with their role.
  static List<IcuArg> getArguments(String text) =>
      collectArgs(parseIcu(text).nodes);

  /// The canonical, ordered parameter list for a message.
  ///
  /// `@key.placeholders` declares the order, but only for names the message
  /// actually uses; names the message uses but metadata omits follow, in
  /// first-appearance order.
  static List<String> getOrderedPlaceholders(
    String text,
    Map<String, PlaceholderInfo>? metadata,
  ) {
    final used = getArguments(text).map((a) => a.name).toList();
    if (metadata == null) return used;

    final usedSet = used.toSet();
    final declared = metadata.keys.where(usedSet.contains).toList();
    final declaredSet = declared.toSet();
    return [...declared, ...used.where((n) => !declaredSet.contains(n))];
  }
}

/// `String(value)` as JavaScript writes it, so numbers from JSON print the
/// same as they do in the VS Code extension (`2`, never `2.0`).
String jsString(Object value) {
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    if (value.abs() < 1e21) return value.toInt().toString();
  }
  return value.toString();
}
