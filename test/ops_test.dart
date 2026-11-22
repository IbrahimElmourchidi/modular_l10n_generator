import 'dart:io';

import 'package:modular_l10n_generator/src/icu/icu_diagnostics.dart';
import 'package:modular_l10n_generator/src/ops/arb_file.dart' as arbs;
import 'package:modular_l10n_generator/src/ops/arb_file.dart' show readArb;
import 'package:modular_l10n_generator/src/ops/check_ops.dart';
import 'package:modular_l10n_generator/src/ops/doctor_ops.dart';
import 'package:modular_l10n_generator/src/ops/exchange_ops.dart';
import 'package:modular_l10n_generator/src/ops/key_ops.dart';
import 'package:modular_l10n_generator/src/ops/locale_ops.dart';
import 'package:modular_l10n_generator/src/ops/maintenance_ops.dart';
import 'package:modular_l10n_generator/src/ops/module_ops.dart';
import 'package:modular_l10n_generator/src/ops/project.dart';
import 'package:modular_l10n_generator/src/ops/pubspec_writer.dart';
import 'package:modular_l10n_generator/src/ops/scan_ops.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

/// A project with an `auth` module in en and ar.
String authProject() {
  final root = tempProject();
  writePubspec(root);
  writeArb(root, 'lib/features/auth/l10n/auth_en.arb', {
    '@@locale': 'en',
    '@@context': 'auth',
    'emailLabel': 'Email',
    'welcome': 'Hi {name}',
    '@welcome': {
      'placeholders': {
        'name': {'type': 'String'}
      },
    },
  });
  writeArb(root, 'lib/features/auth/l10n/auth_ar.arb', {
    '@@locale': 'ar',
    '@@context': 'auth',
    'emailLabel': 'البريد',
    'welcome': '',
  });
  return root;
}

Map<String, Object?> arb(String root, String relative) =>
    readArb(p.join(root, relative));

void main() {
  group('arb files', () {
    test('are written like JSON.stringify(data, null, 2)', () {
      final root = tempProject();
      final path = p.join(root, 'x.arb');
      expect(arbs.writeArb(path, {'a': 'é', 'n': 2.0, 'm': {}}), isTrue);
      expect(File(path).readAsStringSync(),
          '{\n  "a": "é",\n  "n": 2,\n  "m": {}\n}');
      expect(arbs.writeArb(path, {'a': 'é', 'n': 2, 'm': {}}), isFalse);
    });
  });

  group('pubspec writer', () {
    test('edits only the modular_l10n section and keeps comments', () {
      final root = tempProject();
      File(p.join(root, 'pubspec.yaml')).writeAsStringSync(
          'name: app # the app\ndependencies:\n  modular_l10n: ^1.0.0\n');
      updateModularConfig(root, {'class_name': 'ML', 'enabled': true});
      updateModularConfig(root, {'class_name': 'AppL10n'});
      final text = File(p.join(root, 'pubspec.yaml')).readAsStringSync();
      expect(text, contains('name: app # the app'));
      expect(text, contains('  modular_l10n: ^1.0.0'));
      expect(text, contains('class_name: AppL10n'));
      expect(text, contains('enabled: true'));
    });
  });

  group('modules', () {
    test('create-module writes one file per locale and skips existing ones',
        () {
      final root = authProject();
      final project = Project.load(root);
      final r = createModule(project,
          folder: p.join(root, 'lib/features/user_profile'),
          name: 'user_profile',
          locales: ['en', 'ar']);
      expect(r.created, hasLength(2));
      expect(arb(root, 'lib/features/user_profile/l10n/user_profile_en.arb'), {
        '@@locale': 'en',
        '@@context': 'user_profile',
        'userProfileTitle': 'UserProfile Title',
      });
      expect(
          arb(root, 'lib/features/user_profile/l10n/user_profile_ar.arb')[
              'userProfileTitle'],
          '');

      final again = createModule(project.reload(),
          folder: p.join(root, 'lib/features/user_profile'),
          name: 'user_profile',
          locales: ['en', 'ar', 'fr']);
      expect(again.created.map(p.basename), ['user_profile_fr.arb']);
      expect(again.skipped, hasLength(2));
    });

    test('create-module refuses a name another folder already uses', () {
      final root = authProject();
      expect(
        () => createModule(Project.load(root),
            folder: p.join(root, 'lib/other'), name: 'auth', locales: ['en']),
        throwsA(isA<OpException>()),
      );
    });

    test('suggestModuleName turns a folder into snake_case', () {
      expect(suggestModuleName('/x/UserProfile'), 'user_profile');
      expect(suggestModuleName('/x/my-feature'), 'my_feature');
    });

    test('init writes the config and the first module', () {
      final root = tempProject();
      writePubspec(root);
      initProject(root,
          defaultLocale: 'en',
          moduleName: 'app',
          moduleFolder: p.join(root, 'lib/app'));
      final project = Project.load(root);
      expect(project.config.className, 'ML');
      expect(project.modules.single.name, 'app');
    });
  });

  group('keys and locales', () {
    test('add-key writes every locale and metadata in the template', () {
      final root = authProject();
      addKey(Project.load(root),
          module: 'auth',
          key: 'count',
          values: {'en': '{n} items'},
          description: 'Item count',
          placeholders: [PlaceholderSpec.parse('n:int')]);
      expect(arb(root, 'lib/features/auth/l10n/auth_en.arb')['@count'], {
        'description': 'Item count',
        'placeholders': {
          'n': {'type': 'int'}
        },
      });
      expect(arb(root, 'lib/features/auth/l10n/auth_ar.arb')['count'], '');
      expect(
        () => addKey(Project.load(root), module: 'auth', key: 'count'),
        throwsA(isA<OpException>()),
      );
    });

    test('add-locale copies the template with empty values', () {
      final root = authProject();
      addLocale(Project.load(root), 'fr');
      expect(arb(root, 'lib/features/auth/l10n/auth_fr.arb'), {
        '@@locale': 'fr',
        '@@context': 'auth',
        'emailLabel': '',
        'welcome': '',
        '@welcome': {
          'placeholders': {
            'name': {'type': 'String'}
          },
        },
      });
    });

    test('remove-locale deletes files but never the default', () {
      final root = authProject();
      expect(() => removeLocale(Project.load(root), 'en'),
          throwsA(isA<OpException>()));
      removeLocale(Project.load(root), 'ar');
      expect(
          File(p.join(root, 'lib/features/auth/l10n/auth_ar.arb')).existsSync(),
          isFalse);
    });

    test('rename-key keeps position and metadata and updates Dart code', () {
      final root = authProject();
      final dart = File(p.join(root, 'lib/main.dart'))
        ..writeAsStringSync('f(c) => ML.of(c).auth.welcome("x");\n');
      renameKey(Project.load(root),
          module: 'auth', oldKey: 'welcome', newKey: 'greeting');
      expect(arb(root, 'lib/features/auth/l10n/auth_en.arb').keys,
          ['@@locale', '@@context', 'emailLabel', 'greeting', '@greeting']);
      expect(dart.readAsStringSync(), contains('.auth.greeting('));
    });

    test('unused keys are found and removed', () {
      final root = authProject();
      File(p.join(root, 'lib/main.dart'))
          .writeAsStringSync('x(c) => ML.of(c).auth.emailLabel;');
      final project = Project.load(root);
      final unused = findUnusedKeys(project);
      expect(unused, {
        'auth': ['welcome']
      });
      removeKeys(project, unused);
      expect(
          arb(root, 'lib/features/auth/l10n/auth_en.arb')
              .containsKey('@welcome'),
          isFalse);
    });

    test('sort orders keys with metadata after each key', () {
      expect(
        sortArbData(
                {'b': 1, '@a': {}, '@@context': 'x', 'a': 2, '@@locale': 'en'})
            .keys,
        ['@@locale', '@@context', 'a', '@a', 'b'],
      );
    });
  });

  group('check', () {
    test('reports empty translations, ICU errors and direct imports', () {
      final root = authProject();
      writeArb(root, 'lib/features/home/l10n/home_en.arb', {
        '@@locale': 'en',
        '@@context': 'home',
        'items': '{n, plural, one{# item}}',
      });
      File(p.join(root, 'lib/main.dart')).writeAsStringSync(
          "import 'generated/modular_l10n/auth_l10n.dart';\n");
      final codes =
          checkProject(Project.load(root)).map((i) => i.code).toList();
      expect(
          codes,
          containsAll([
            'empty-translation',
            'icu-missing-other',
            'missing-locale-file',
            'direct-module-import'
          ]));
    });

    test('ICU diagnostics flag arguments the template lacks', () {
      final d = diagnoseIcuMessage('k', 'Hi {who}', canonicalArgs: const []);
      expect(d.map((e) => e.code), ['icu-argument-mismatch']);
    });

    test('doctor reports missing dependencies', () {
      final root = authProject();
      final titles = diagnoseProject(root).map((i) => i.title);
      expect(titles, contains(startsWith('Missing dependencies')));
    });
  });

  group('exchange', () {
    test('pseudo-localizes text but not placeholders', () {
      expect(pseudoLocalize('Hi {name}', 0), '[Ĥï {name}]');
      expect(pseudoLocalize('ab', 0.5), '[åƀ ~]');
    });

    test('CSV export and import round-trip', () {
      final root = authProject();
      final project = Project.load(root);
      final csv = p.join(root, 't.csv');
      exportTranslations(project, outputPath: csv);
      final text = File(csv).readAsStringSync();
      expect(File(csv).readAsBytesSync().take(3), [0xEF, 0xBB, 0xBF]);
      expect(text, contains('Module,Key,Description,ar,en\n'));

      File(csv).writeAsStringSync(
          text.replaceFirst('auth,welcome,,,', 'auth,welcome,,"أهلا {name}",'));
      final result = importTranslations(Project.load(root), csv);
      expect(result.changes.single.key, 'welcome');
      expect(arb(root, 'lib/features/auth/l10n/auth_ar.arb')['welcome'],
          'أهلا {name}');
    });

    test('XLIFF import fills targets', () {
      final root = authProject();
      final xlf = p.join(root, 't.xlf');
      exportTranslations(Project.load(root), outputPath: xlf);
      File(xlf).writeAsStringSync(File(xlf).readAsStringSync().replaceFirst(
          '<target></target>', '<target>مرحبا &amp; {name}</target>'));
      importTranslations(Project.load(root), xlf);
      expect(arb(root, 'lib/features/auth/l10n/auth_ar.arb')['welcome'],
          'مرحبا & {name}');
    });

    test('migrate splits Flutter Intl keys by prefix', () {
      final root = tempProject();
      writePubspec(root);
      writeArb(root, 'lib/l10n/intl_en.arb', {
        'authLogin': 'Login',
        'ok': 'OK',
        '@ok': {'description': 'd'}
      });
      final project = Project.load(root);
      migrateFromFlutterIntl(project, files: findFlutterIntlArbs(root));
      expect(arb(root, 'lib/features/common/l10n/common_en.arb'), {
        '@@locale': 'en',
        '@@context': 'common',
        'ok': 'OK',
        '@ok': {'description': 'd'},
      });
      expect(arb(root, 'lib/features/auth/l10n/auth_en.arb')['authLogin'],
          'Login');
    });
  });

  group('hardcoded strings', () {
    test('are found and extracted, dropping a now-invalid const', () {
      final root = authProject();
      final file = File(p.join(root, 'lib/ui.dart'))
        ..writeAsStringSync("w() => const Text('Sign in now, \$user');\n");
      final found = scanHardcodedStrings(Project.load(root));
      expect(found.single.literal, "'Sign in now, \$user'");

      final plan = planExtract(file.path, 1, found.single.column);
      expect(plan.arbValue, 'Sign in now, {user}');
      expect(plan.suggestedKey, 'signInNow');
      extractString(Project.load(root), plan, module: 'auth', key: 'signIn');
      expect(file.readAsStringSync(),
          'w() => Text(ML.of(context).auth.signIn(user));\n');
      expect(arb(root, 'lib/features/auth/l10n/auth_en.arb')['signIn'],
          'Sign in now, {user}');
    });
  });
}
