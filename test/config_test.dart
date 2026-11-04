import 'package:modular_l10n_generator/modular_l10n_generator.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('defaults when pubspec.yaml has no modular_l10n section', () {
    final root = tempProject();
    writePubspec(root);
    final config = loadConfig(root);
    expect(config.className, 'ML');
    expect(config.outputDir, 'lib/generated/modular_l10n');
    expect(config.arbFilePattern, '**/l10n/*.arb');
    expect(config.moduleAccess, ModuleAccess.part);
    expect(config.logLevel, LogLevel.warning);
  });

  test('reads every key, and flags override pubspec per key', () {
    final root = tempProject();
    writePubspec(root, '''
  class_name: Strings
  main_locale: zh-Hans
  output_dir: lib/l10n_out
  arb_dir_pattern: "lib/**/*.arb"
  generate_combined_arb: false
  use_deferred_loading: true
  log_level: debug
  module_access: library
''');
    final fromPubspec = loadConfig(root);
    expect(fromPubspec.className, 'Strings');
    expect(fromPubspec.defaultLocale, 'zh_Hans');
    expect(fromPubspec.outputDir, 'lib/l10n_out');
    expect(fromPubspec.arbFilePattern, 'lib/**/*.arb');
    expect(fromPubspec.generateCombinedArb, isFalse);
    expect(fromPubspec.useDeferredLoading, isTrue);
    expect(fromPubspec.logLevel, LogLevel.verbose);
    expect(fromPubspec.moduleAccess, ModuleAccess.library);

    final overridden = loadConfig(
      root,
      overrides: const ConfigOverrides(
          className: 'L', moduleAccess: ModuleAccess.part),
    );
    expect(overridden.className, 'L');
    expect(overridden.moduleAccess, ModuleAccess.part);
    expect(overridden.outputDir, 'lib/l10n_out');
  });

  test('values of the wrong type or unknown enums fall back to defaults', () {
    final root = tempProject();
    writePubspec(root, '''
  class_name: 42
  module_access: modules
  generate_combined_arb: "yes"
''');
    final config = loadConfig(root);
    expect(config.className, 'ML');
    expect(config.moduleAccess, ModuleAccess.part);
    expect(config.generateCombinedArb, isTrue);
  });

  test('a modular_l10n dependency is not mistaken for the config section', () {
    final root = tempProject();
    writePubspec(root, '');
    final reader = PubspecReader(root);
    expect(reader.readConfig(), isNull);
  });

  test('invalid YAML is reported, not silently ignored', () {
    final root = tempProject();
    writePubspec(root, '  class_name: [unclosed\n');
    expect(() => loadConfig(root), throwsA(isA<PubspecException>()));
  });

  test('findProjectRoot walks up to the nearest pubspec.yaml', () {
    final root = tempProject();
    writePubspec(root);
    writeArb(root, 'lib/a/b/l10n/en.arb', {});
    expect(findProjectRoot('$root/lib/a/b/l10n'), root);
  });
}
