import 'dart:async';
import 'dart:io';

import 'package:modular_l10n_generator/modular_l10n_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'helpers.dart';

Future<ProcessResult> _cli(List<String> args) => Process.run(
      Platform.resolvedExecutable,
      ['run', p.join('bin', 'modular_l10n_generator.dart'), ...args],
    );

void main() {
  test('packageVersion matches pubspec.yaml', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    expect(packageVersion, pubspec['version']);
  });

  test('no command means generate; exit codes reflect the outcome', () async {
    final root = tempProject();
    writePubspec(root);

    final empty = await _cli(['--root', root]);
    expect(empty.exitCode, 1, reason: '${empty.stderr}');

    writeArb(root, 'lib/a/l10n/en.arb',
        {'@@locale': 'en', '@@context': 'a', 'k': 'v'});
    writeArb(root, 'lib/a/l10n/xx.arb', {'@@locale': 'xx', '@@context': 'a'});

    final ok = await _cli(['--root', root]);
    expect(ok.exitCode, 0, reason: '${ok.stderr}');
    expect(ok.stdout, contains('Generated 1 key(s)'));

    final strict = await _cli(['generate', '--root', root, '--fatal-warnings']);
    expect(strict.exitCode, 1);
  });

  test('usage errors exit with 64', () async {
    final result = await _cli(['generate', '--module-access', 'nope']);
    expect(result.exitCode, 64);
  });

  test('watcher regenerates after a relevant change only', () async {
    final root = tempProject();
    writePubspec(root);
    writeArb(root, 'lib/a/l10n/en.arb',
        {'@@locale': 'en', '@@context': 'a', 'k': 'v'});

    var runs = 0;
    final changed = StreamController<void>.broadcast();
    final watcher = ArbWatcher(
      rootPath: root,
      patternOf: () => '**/l10n/*.arb',
      debounce: const Duration(milliseconds: 50),
      onChange: () {
        runs++;
        changed.add(null);
      },
    );
    addTearDown(watcher.stop);
    await watcher.start();

    expect(watcher.isRelevant(p.join(root, 'lib/a/l10n/en.arb')), isTrue);
    expect(watcher.isRelevant(p.join(root, 'lib/a/l10n/intl_en.arb')), isFalse);
    expect(watcher.isRelevant(p.join(root, 'lib/a/notes.txt')), isFalse);
    expect(watcher.isRelevant(p.join(root, 'pubspec.yaml')), isTrue);

    final next = changed.stream.first.timeout(const Duration(seconds: 10));
    writeArb(root, 'lib/a/l10n/en.arb',
        {'@@locale': 'en', '@@context': 'a', 'k': 'changed'});
    await next;
    expect(runs, 1);
  });
}
