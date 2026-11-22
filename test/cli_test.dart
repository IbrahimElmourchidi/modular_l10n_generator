import 'dart:async';
import 'dart:io';

import 'package:modular_l10n_generator/modular_l10n_generator.dart';
import 'package:modular_l10n_generator/src/ops/arb_file.dart' show readArb;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'helpers.dart';

/// The CLI compiled once, so each call does not recompile it.
late String _snapshot;

Future<ProcessResult> _cli(List<String> args) =>
    Process.run(Platform.resolvedExecutable, [_snapshot, ...args]);

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('modular_l10n_cli_');
    _snapshot = p.join(dir.path, 'cli.dill');
    final compiled = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'kernel',
      p.join('bin', 'modular_l10n_generator.dart'),
      '-o',
      _snapshot,
    ]);
    expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
  });
  tearDownAll(() => File(_snapshot).parent.deleteSync(recursive: true));

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

  group('project commands', () {
    test('set up a project end to end without prompts', () async {
      final root = tempProject();
      writePubspec(root);
      final dir = p.join(root, 'lib', 'features');

      Future<ProcessResult> run(List<String> args) async {
        final r = await _cli([...args, '--root', root]);
        expect(r.exitCode, 0, reason: '${args.first}: ${r.stdout}${r.stderr}');
        return r;
      }

      await run([
        'init',
        '--default-locale',
        'en',
        '--module',
        'app',
        '--dir',
        p.join(dir, 'app')
      ]);
      await run(
          ['create-module', '--dir', p.join(dir, 'auth'), '--locales', 'en']);
      await run(['add-locale', 'ar']);
      await run([
        'add-key',
        '-m',
        'auth',
        '-k',
        'email',
        '--value',
        'en=Email',
        '--value',
        'ar=البريد'
      ]);
      await run([
        'rename-key',
        '-m',
        'auth',
        '--from',
        'email',
        '--to',
        'emailLabel'
      ]);

      final ar = readArb(p.join(dir, 'auth', 'l10n', 'auth_ar.arb'));
      expect(ar['emailLabel'], 'البريد');
      expect(
          File(p.join(root, 'lib/generated/modular_l10n/auth_l10n.dart'))
              .readAsStringSync(),
          contains('emailLabel'));

      // Empty translations are warnings, not errors.
      final check = await run(['check']);
      expect(check.stderr, contains('empty-translation'));
      final strict = await _cli(['check', '--fatal-warnings', '--root', root]);
      expect(strict.exitCode, 1);
    });

    test('a missing value is a usage error when there is no terminal',
        () async {
      final root = tempProject();
      writePubspec(root);
      final r = await _cli(['add-key', '--root', root]);
      expect(r.exitCode, anyOf(1, 64), reason: '${r.stderr}');
      final create = await _cli(['create-module', '--root', root]);
      expect(create.exitCode, 64, reason: '${create.stderr}');
      expect(create.stderr, contains('Missing --dir'));
    });

    test('destructive commands need --yes without a terminal', () async {
      final root = tempProject();
      writePubspec(root);
      writeArb(root, 'lib/a/l10n/a_en.arb',
          {'@@locale': 'en', '@@context': 'a', 'k': 'v'});
      writeArb(root, 'lib/a/l10n/a_fr.arb',
          {'@@locale': 'fr', '@@context': 'a', 'k': 'v'});
      expect(
          (await _cli(['remove-locale', 'fr', '--root', root])).exitCode, 64);
      expect(File(p.join(root, 'lib/a/l10n/a_fr.arb')).existsSync(), isTrue);
      expect(
          (await _cli(['remove-locale', 'fr', '--yes', '--root', root]))
              .exitCode,
          0);
      expect(File(p.join(root, 'lib/a/l10n/a_fr.arb')).existsSync(), isFalse);
    });

    test('sort --check fails on unsorted files and passes after sort',
        () async {
      final root = tempProject();
      writePubspec(root);
      writeArb(root, 'lib/a/l10n/a_en.arb',
          {'@@locale': 'en', '@@context': 'a', 'b': 'B', 'a': 'A'});
      expect((await _cli(['sort', '--check', '--root', root])).exitCode, 1);
      expect((await _cli(['sort', '--root', root])).exitCode, 0);
      expect((await _cli(['sort', '--check', '--root', root])).exitCode, 0);
    });

    test('gui refuses to start without a terminal', () async {
      final root = tempProject();
      writePubspec(root);
      final r = await _cli(['gui', '--root', root]);
      expect(r.exitCode, 1);
      expect(r.stderr, contains('interactive terminal'));
    });
  });
}
