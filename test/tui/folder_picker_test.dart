import 'dart:io';

import 'package:modular_l10n_generator/src/tui/widgets/folder_picker.dart';
import 'package:nocterm/nocterm.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('navigates into a folder and selects it', () async {
    final root = tempProject();
    Directory(p.join(root, 'lib', 'features', 'auth'))
        .createSync(recursive: true);
    Directory(p.join(root, 'lib', 'core')).createSync(recursive: true);

    String? picked;
    await testNocterm('folder picker', (tester) async {
      await tester.pumpComponent(
        FolderPicker(rootPath: root, onSelected: (path) => picked = path),
      );
      expect(tester.terminalState, containsText('lib/'));
      expect(tester.terminalState, containsText('Create here'));
      expect(tester.terminalState, containsText('features/'));

      // Entries: Create here, New folder, .., core, features.
      for (var i = 0; i < 4; i++) {
        await tester.sendArrowDown();
      }
      await tester.sendEnter(); // into features/
      expect(tester.terminalState, containsText('lib/features/'));
      expect(tester.terminalState, containsText('auth/'));

      await tester.sendArrowLeft(); // back up to lib/
      expect(tester.terminalState, isNot(containsText('lib/features/')));

      await tester.sendEnter(); // selection was restored on features/
      await tester.sendArrowUp();
      await tester.sendArrowUp();
      await tester.sendArrowUp();
      await tester.sendEnter(); // Create here
    });
    expect(picked, p.join(root, 'lib', 'features'));
  });

  test('creates a new folder and enters it', () async {
    final root = tempProject();
    Directory(p.join(root, 'lib')).createSync();

    await testNocterm('new folder', (tester) async {
      await tester.pumpComponent(
        FolderPicker(rootPath: root, onSelected: (_) {}),
      );
      await tester.sendKeyEvent(
        const KeyboardEvent(logicalKey: LogicalKey.keyN, character: 'n'),
      );
      await tester.enterText('profile');
      await tester.sendEnter();
      expect(tester.terminalState, containsText('lib/profile/'));
    });
    expect(Directory(p.join(root, 'lib', 'profile')).existsSync(), isTrue);
  });
}
