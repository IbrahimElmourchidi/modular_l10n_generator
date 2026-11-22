import 'dart:io';

import 'package:modular_l10n_generator/src/ops/arb_file.dart' show readArb;
import 'package:modular_l10n_generator/src/tui/actions.dart';
import 'package:modular_l10n_generator/src/tui/app.dart';
import 'package:modular_l10n_generator/src/tui/controller.dart';
import 'package:nocterm/nocterm.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers.dart';

KeyboardEvent char(String c) => KeyboardEvent(
      logicalKey: LogicalKey.fromCharacter(c)!,
      character: c,
    );

/// NoctermApp detects the terminal's brightness first (up to 50 ms); keys
/// sent before that are not delivered.
Future<void> start(NoctermTester tester, GuiController controller) async {
  await tester
      .pumpComponent(NoctermApp(child: L10nApp(controller: controller)));
  await Future<void>.delayed(const Duration(milliseconds: 120));
  await tester.pump();
}

Future<void> pumpABit(NoctermTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  test('action shortcuts are unique and not taken by global keys', () {
    // j/k move, q quits, w/v/r/? are global; a shortcut on one of them
    // would never fire.
    const reserved = {'j', 'k', 'q', 'w', 'v', 'r', '?'};
    final shortcuts = [
      for (final a in guiActions)
        if (a.shortcut != null) a.shortcut!,
    ];
    expect(shortcuts.toSet(), hasLength(shortcuts.length));
    expect(shortcuts.where(reserved.contains).toList(), <String>[]);
  });

  test('create a module by browsing to a folder', () async {
    final root = tempProject();
    writePubspec(root, '  class_name: ML\n');
    writeArb(root, 'lib/features/auth/l10n/auth_en.arb',
        {'@@locale': 'en', '@@context': 'auth', 'emailLabel': 'Email'});
    writeArb(root, 'lib/features/auth/l10n/auth_ar.arb',
        {'@@locale': 'ar', '@@context': 'auth', 'emailLabel': 'البريد'});
    Directory(p.join(root, 'lib', 'features', 'profile'))
        .createSync(recursive: true);

    final controller = GuiController(root);
    addTearDown(controller.dispose);

    await testNocterm('gui', (tester) async {
      await start(tester, controller);
      expect(tester.terminalState, containsText('Modular L10n'));
      expect(tester.terminalState, containsText('Create module'));
      expect(tester.terminalState, containsText('auth'));

      // Shortcut m opens Create module; the folder picker starts in lib/.
      await tester.sendKeyEvent(char('m'));
      await pumpABit(tester);
      expect(tester.terminalState, containsText('Pick the feature folder'));
      // Entries: Create here, New folder, .., features → open features.
      for (var i = 0; i < 3; i++) {
        await tester.sendArrowDown();
      }
      await tester.sendEnter();
      expect(tester.terminalState, containsText('lib/features/'));
      // Entries: Create here, New folder, .., auth, profile → open profile.
      for (var i = 0; i < 4; i++) {
        await tester.sendArrowDown();
      }
      await tester.sendEnter();
      expect(tester.terminalState, containsText('lib/features/profile/'));
      await tester.sendArrowUp();
      await tester.sendArrowUp();
      await tester.sendArrowUp();
      await tester.sendEnter(); // ▶ Create here
      await pumpABit(tester);

      expect(tester.terminalState, containsText('Module name'));
      await tester.sendEnter(); // accept "profile"
      await pumpABit(tester);

      expect(tester.terminalState, containsText('Locales'));
      expect(tester.terminalState, containsText('[x] ar'));
      await tester.sendEnter(); // keep ar + en
      await pumpABit(tester);

      expect(tester.terminalState, containsText('Module created'));
      expect(tester.terminalState, containsText('profile_en.arb'));
      await tester.sendEnter();
      await pumpABit(tester);
      expect(tester.terminalState, containsText('Overview'));
    }, size: const Size(110, 32));

    final en =
        readArb(p.join(root, 'lib/features/profile/l10n/profile_en.arb'));
    expect(en, {
      '@@locale': 'en',
      '@@context': 'profile',
      'profileTitle': 'Profile Title'
    });
    expect(
        File(p.join(root, 'lib/features/profile/l10n/profile_ar.arb'))
            .existsSync(),
        isTrue);
    expect(
        File(p.join(root, 'lib/generated/modular_l10n/profile_l10n.dart'))
            .existsSync(),
        isTrue);
  });

  test('Esc cancels an action without changing anything', () async {
    final root = tempProject();
    writePubspec(root);
    writeArb(root, 'lib/a/l10n/a_en.arb',
        {'@@locale': 'en', '@@context': 'a', 'x': 'X'});
    final controller = GuiController(root);
    addTearDown(controller.dispose);

    await testNocterm('cancel', (tester) async {
      await start(tester, controller);
      await tester.sendKeyEvent(char('l')); // Add locale
      await pumpABit(tester);
      expect(tester.terminalState, containsText('Locale to add'));
      await tester.enterText('xx_NOPE');
      await tester.sendEnter();
      expect(tester.terminalState, containsText('Unknown locale'));
      await tester.sendEscape();
      await pumpABit(tester);
      expect(tester.terminalState, containsText('Overview'));
    }, size: const Size(110, 32));
    expect(Directory(p.join(root, 'lib/a/l10n')).listSync(), hasLength(1));
  });
}
