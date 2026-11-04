import 'package:modular_l10n_generator/src/collation.dart';
import 'package:modular_l10n_generator/src/json_writer.dart';
import 'package:modular_l10n_generator/src/locales.dart';
import 'package:modular_l10n_generator/src/ordinals/ordinal_codegen.dart';
import 'package:test/test.dart';

void main() {
  group('collate', () {
    test('matches ICU root order, as captured from Node localeCompare', () {
      // Captured from: [...].sort((a, b) => a.localeCompare(b, 'en'))
      const icuOrder = [
        'a_b',
        'a-b',
        'a.b',
        'a/1',
        'a/b',
        'A/b',
        'a1',
        'ab',
        'aB',
        'Ab'
      ];
      final shuffled = [...icuOrder.reversed]..sort(collate);
      expect(shuffled, icuOrder);
    });

    test('a module directory sorts after its underscore-suffixed sibling', () {
      final paths = ['/p/lib/auth/l10n/en.arb', '/p/lib/auth_extra/l10n/en.arb']
        ..sort(collate);
      expect(paths.first, '/p/lib/auth_extra/l10n/en.arb');
    });
  });

  group('ordinals', () {
    test('locale fallback walks one subtag at a time', () {
      expect(ordinalGroupFor('en'), 'en');
      expect(ordinalGroupFor('en_GB'), 'en');
      expect(ordinalGroupFor('zh_Hans_CN'), 'other');
      expect(ordinalGroupFor('kok_Latn'), 'kok');
      expect(ordinalGroupFor('xx'), isNull);
    });

    test('compiles only the groups in use and reports unmapped locales', () {
      final result = compileOrdinals(['en', 'fr', 'xx']);
      expect(result.content, contains('String _ordinalEn(int n)'));
      expect(result.content, contains('String _ordinalFr(int n)'));
      expect(result.content, isNot(contains('_ordinalKw')));
      expect(result.content, contains('if (v % 10 == 1 && !(v % 100 == 11))'));
      expect(result.unmapped, ['xx']);
    });

    test('every CLDR rule compiles', () {
      expect(
        () => compileOrdinals(
            ['af', 'az', 'kw', 'lij', 'or', 'cy', 'blo', 'kk', 'ka']),
        returnsNormally,
      );
    });
  });

  group('encodeJsonLikeJs', () {
    test('formats like JSON.stringify(value, null, 2)', () {
      expect(
        encodeJsonLikeJs({
          'a': 2.0,
          'b': 2.5,
          'c': {},
          'd': 'x"\\\n\u0001',
          'e': {'f': true, 'g': null},
        }),
        '{\n  "a": 2,\n  "b": 2.5,\n  "c": {},\n  "d": "x\\"\\\\\\n\\u0001",\n'
        '  "e": {\n    "f": true,\n    "g": null\n  }\n}',
      );
    });
  });

  group('isKnownLocale', () {
    test('accepts listed languages with any region or a known script', () {
      expect(isKnownLocale('en'), isTrue);
      expect(isKnownLocale('en_XX'), isTrue);
      expect(isKnownLocale('zh_Hant_TW'), isTrue);
      expect(isKnownLocale('sr_Latn_ZZ'), isTrue);
    });

    test('rejects unknown languages and scripts', () {
      expect(isKnownLocale('xx'), isFalse);
      expect(isKnownLocale('en_Xxxx_US'), isFalse);
      expect(isKnownLocale('en_US_POSIX_X'), isFalse);
    });
  });
}
