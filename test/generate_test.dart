import 'dart:io';

import 'package:modular_l10n_generator/modular_l10n_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

GenerationResult _generate(String root,
        {StringBuffer? err, bool force = false}) =>
    runGeneration(
      rootPath: root,
      logger: Logger(out: StringBuffer(), err: err ?? StringBuffer()),
      force: force,
    );

void main() {
  group('scanner', () {
    test('skips Flutter Intl, excluded and hidden directories', () {
      final root = tempProject();
      writeArb(root, 'lib/auth/l10n/en.arb',
          {'@@locale': 'en', '@@context': 'auth'});
      writeArb(root, 'lib/l10n/intl_en.arb', {'@@locale': 'en'});
      writeArb(
          root, 'build/x/l10n/en.arb', {'@@locale': 'en', '@@context': 'b'});
      writeArb(root, 'lib/generated/l10n/en.arb',
          {'@@locale': 'en', '@@context': 'g'});
      writeArb(
          root, '.hidden/l10n/en.arb', {'@@locale': 'en', '@@context': 'h'});
      // A segment that merely contains an excluded name still counts.
      writeArb(root, 'lib/build_order/l10n/en.arb',
          {'@@locale': 'en', '@@context': 'orders'});

      final scan = ModuleScanner(root, '**/l10n/*.arb').scan();
      expect(scan.modules.map((m) => m.name), ['auth', 'orders']);
      expect(
          scan.skippedFlutterIntlFiles, [p.join('lib', 'l10n', 'intl_en.arb')]);
    });

    test('rejects files without @@context or with an unknown locale', () {
      final root = tempProject();
      writeArb(root, 'lib/a/l10n/en.arb', {'@@locale': 'en'});
      writeArb(root, 'lib/b/l10n/en.arb', {'@@locale': 'qq', '@@context': 'b'});
      final scan = ModuleScanner(root, '**/l10n/*.arb').scan();
      expect(scan.modules, isEmpty);
      expect(scan.validationErrors, hasLength(2));
    });
  });

  group('runGeneration', () {
    test('generates, then writes nothing when inputs are unchanged', () {
      final root = tempProject();
      writePubspec(root);
      writeArb(root, 'lib/auth/l10n/en.arb', {
        '@@locale': 'en',
        '@@context': 'auth',
        'hello': 'Hello {name}',
      });

      final first = _generate(root);
      expect(first.success, isTrue);
      expect(first.keyCount, 1);
      final module =
          File(p.join(root, 'lib/generated/modular_l10n/auth_l10n.dart'));
      expect(module.readAsStringSync(), contains('String hello(Object name)'));

      expect(_generate(root).writtenFiles, isEmpty);
    });

    test('fails when no modular ARB file is found', () {
      final root = tempProject();
      writePubspec(root);
      final err = StringBuffer();
      expect(_generate(root, err: err).success, isFalse);
      expect(err.toString(), contains('No valid ARB files found'));
    });

    test('enabled: false is a successful no-op', () {
      final root = tempProject();
      writePubspec(root, '  enabled: false\n');
      writeArb(root, 'lib/a/l10n/en.arb', {'@@locale': 'en', '@@context': 'a'});
      final result = _generate(root);
      expect(result.success, isTrue);
      expect(result.skipped, isTrue);
      expect(Directory(p.join(root, 'lib/generated')).existsSync(), isFalse);
    });

    test('refuses a class name that collides with Flutter Intl unless forced',
        () {
      final root = tempProject();
      File(p.join(root, 'pubspec.yaml')).writeAsStringSync(
        'name: app\nflutter_intl:\n  class_name: ML\n',
      );
      writeArb(root, 'lib/a/l10n/en.arb', {'@@locale': 'en', '@@context': 'a'});

      final err = StringBuffer();
      expect(_generate(root, err: err).success, isFalse);
      expect(err.toString(), contains('Class name "ML"'));

      final forced = _generate(root, force: true);
      expect(forced.success, isTrue);
      expect(forced.warningCount, 1);
    });

    test('an output directory nested in Flutter Intl\'s is allowed', () {
      final root = tempProject();
      // Flutter Intl's default output is lib/generated; ours is inside it.
      File(p.join(root, 'pubspec.yaml')).writeAsStringSync(
        'name: app\nflutter_intl:\n  enabled: true\n',
      );
      writeArb(root, 'lib/a/l10n/en.arb', {'@@locale': 'en', '@@context': 'a'});
      final result = _generate(root);
      expect(result.success, isTrue);
      expect(result.warningCount, 0);
    });

    test('the same output directory as Flutter Intl is refused', () {
      final root = tempProject();
      File(p.join(root, 'pubspec.yaml')).writeAsStringSync(
        'name: app\nflutter_intl:\n  output_dir: lib/gen\n'
        'modular_l10n:\n  output_dir: lib/gen/\n',
      );
      writeArb(root, 'lib/a/l10n/en.arb', {'@@locale': 'en', '@@context': 'a'});
      final err = StringBuffer();
      expect(_generate(root, err: err).success, isFalse);
      expect(err.toString(), contains('same as Flutter Intl'));
    });

    test('falls back to the first locale when the default is missing', () {
      final root = tempProject();
      writePubspec(root, '  default_locale: fr\n');
      writeArb(root, 'lib/a/l10n/de.arb',
          {'@@locale': 'de', '@@context': 'a', 'k': 'v'});
      final err = StringBuffer();
      final result = _generate(root, err: err);
      expect(result.success, isTrue);
      expect(
          err.toString(), contains('Configured default locale "fr" not found'));
    });
  });
}
