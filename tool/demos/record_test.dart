// Records the GUI demos shown in the docs.
//
// Drives the real terminal app through nocterm's test harness against a
// sample project and writes every frame (characters and colours) to
// tool/demos/frames/<demo>.json. tool/demos/render.mjs turns those into GIFs.
//
//   dart test tool/demos/record_test.dart
//   node tool/demos/render.mjs
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:modular_l10n_generator/src/tui/app.dart';
import 'package:modular_l10n_generator/src/tui/controller.dart';
import 'package:nocterm/nocterm.dart' hide isEmpty;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _size = Size(100, 28);
const _theme = TuiThemeData.dark;
final _outDir = p.join('tool', 'demos', 'frames');

String _hex(Color? c, Color fallback) {
  final v = (c == null || c.isDefault) ? fallback : c;
  return '#${[
    v.red,
    v.green,
    v.blue
  ].map((x) => x.toRadixString(16).padLeft(2, '0')).join()}';
}

/// Collects frames; each frame is shown for [hold] milliseconds.
class Recorder {
  Recorder(this.tester);

  final NoctermTester tester;
  final frames = <Map<String, Object?>>[];

  Future<void> snap([int hold = 120]) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    final buffer = tester.terminalState.buffer;
    final rows = <List<List<Object>>>[];
    for (var y = 0; y < _size.height; y++) {
      final runs = <List<Object>>[];
      for (var x = 0; x < _size.width; x++) {
        final cell = buffer.getCell(x, y);
        final s = cell.style;
        var fg = _hex(s.color, _theme.onSurface);
        var bg = _hex(s.backgroundColor, _theme.background);
        if (s.reverse) (fg, bg) = (bg, fg);
        final bold = s.fontWeight == FontWeight.bold ? 1 : 0;
        final ch = cell.char.isEmpty ? ' ' : cell.char;
        final last = runs.isEmpty ? null : runs.last;
        if (last != null && last[1] == fg && last[2] == bg && last[3] == bold) {
          last[0] = '${last[0]}$ch';
        } else {
          runs.add([ch, fg, bg, bold]);
        }
      }
      rows.add(runs);
    }
    final encoded = jsonEncode(rows);
    if (frames.isNotEmpty && frames.last['rows'] == encoded) {
      frames.last['ms'] = (frames.last['ms'] as int) + hold;
      return;
    }
    frames.add({'ms': hold, 'rows': encoded});
  }

  Future<void> key(KeyboardEvent e, [int hold = 350]) async {
    await tester.sendKeyEvent(e);
    await snap(hold);
  }

  Future<void> char(String c, [int hold = 350]) => key(_char(c), hold);
  Future<void> enter([int hold = 600]) => key(_k(LogicalKey.enter), hold);
  Future<void> down([int hold = 220]) => key(_k(LogicalKey.arrowDown), hold);
  Future<void> up([int hold = 220]) => key(_k(LogicalKey.arrowUp), hold);
  Future<void> space([int hold = 300]) => key(_k(LogicalKey.space, ' '), hold);
  Future<void> esc([int hold = 500]) => key(_k(LogicalKey.escape), hold);

  /// Types [text] one character at a time.
  Future<void> type(String text) async {
    for (final c in text.split('')) {
      await tester.enterText(c);
      await snap(55);
    }
    await snap(400);
  }

  Future<void> backspace(int n) async {
    for (var i = 0; i < n; i++) {
      await tester.sendKeyEvent(_k(LogicalKey.backspace));
      await snap(40);
    }
  }

  void save(String name) {
    Directory(_outDir).createSync(recursive: true);
    File(p.join(_outDir, '$name.json')).writeAsStringSync(jsonEncode({
      'cols': _size.width.toInt(),
      'rows': _size.height.toInt(),
      'background': _hex(null, _theme.background),
      'frames': [
        for (final f in frames)
          {'ms': f['ms'], 'rows': jsonDecode(f['rows'] as String)}
      ],
    }));
  }
}

KeyboardEvent _k(LogicalKey key, [String? c]) =>
    KeyboardEvent(logicalKey: key, character: c);
KeyboardEvent _char(String c) =>
    KeyboardEvent(logicalKey: LogicalKey.fromCharacter(c)!, character: c);

void _write(String root, String relative, String content) {
  final file = File(p.join(root, relative))..createSync(recursive: true);
  file.writeAsStringSync(content);
}

String _arb(Map<String, Object?> json) =>
    const JsonEncoder.withIndent('  ').convert(json);

/// A small Flutter app: auth and home modules in en and fr, a profile
/// feature folder without translations, and a screen with hardcoded text.
String _sampleProject() {
  final tmp = Directory.systemTemp.createTempSync('ml10n_demo_');
  addTearDown(() => tmp.deleteSync(recursive: true));
  final root = p.join(tmp.path, 'shop_app');
  _write(root, 'pubspec.yaml', '''
name: shop_app
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  intl: any
modular_l10n:
  class_name: ML
  default_locale: en
''');
  _write(
      root,
      'lib/features/auth/l10n/auth_en.arb',
      _arb({
        '@@locale': 'en',
        '@@context': 'auth',
        'emailLabel': 'Email',
        'passwordLabel': 'Password',
        'signIn': 'Sign in',
        'forgotPassword': 'Forgot your password?',
      }));
  _write(
      root,
      'lib/features/auth/l10n/auth_fr.arb',
      _arb({
        '@@locale': 'fr',
        '@@context': 'auth',
        'emailLabel': 'E-mail',
        'passwordLabel': 'Mot de passe',
        'signIn': '',
      }));
  _write(
      root,
      'lib/features/home/l10n/home_en.arb',
      _arb({
        '@@locale': 'en',
        '@@context': 'home',
        'homeTitle': 'Home',
        'cartItems':
            '{count, plural, =0{Your cart is empty} one{1 item} other{{count} items}}',
        '@cartItems': {
          'placeholders': {
            'count': {'type': 'int'}
          }
        },
      }));
  _write(
      root,
      'lib/features/home/l10n/home_fr.arb',
      _arb({
        '@@locale': 'fr',
        '@@context': 'home',
        'homeTitle': 'Accueil',
        'cartItems':
            '{count, plural, =0{Votre panier est vide} one{1 article} other{{count} articles}}',
      }));
  Directory(p.join(root, 'lib/features/profile')).createSync(recursive: true);
  _write(root, 'lib/features/profile/profile_screen.dart', r'''
import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your profile')),
      body: Column(children: [
        Text('Signed in as $name'),
        ElevatedButton(onPressed: () {}, child: const Text('Sign out')),
      ]),
    );
  }
}
''');
  return root;
}

Future<void> _demo(String name, Future<void> Function(Recorder r) script) =>
    testNocterm(name, (tester) async {
      final root = _sampleProject();
      final controller = GuiController(root)..generate();
      addTearDown(controller.dispose);
      controller.logs.clear();
      await tester.pumpComponent(
          NoctermApp(theme: _theme, child: L10nApp(controller: controller)));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final r = Recorder(tester);
      await r.snap(1200);
      await script(r);
      await r.snap(2500);
      r.save(name);
    }, size: _size);

void main() {
  test('tour', () async {
    await _demo('tour', (r) async {
      for (var i = 0; i < 7; i++) {
        await r.down(450);
      }
      for (var i = 0; i < 7; i++) {
        await r.up(120);
      }
      await r.char('?', 2500);
      await r.esc(800);
      await r.char('g', 2500);
      await r.enter(800);
    });
  });

  test('create-module', () async {
    await _demo('create-module', (r) async {
      await r.char('m', 1200);
      for (var i = 0; i < 3; i++) {
        await r.down(300);
      }
      await r.enter(900); // features/
      // Create here, New folder, .., auth, home, profile.
      for (var i = 0; i < 5; i++) {
        await r.down(300);
      }
      await r.enter(900); // profile/
      for (var i = 0; i < 3; i++) {
        await r.up(250);
      }
      await r.enter(1200); // ▶ Create here
      await r.enter(1200); // accept "profile"
      await r.enter(); // en + fr
      await r.snap(2500);
      await r.enter(800);
    });
  });

  test('add-key', () async {
    await _demo('add-key', (r) async {
      await r.char('a', 900);
      await r.down(400); // home
      await r.enter(900);
      await r.type('welcomeBack');
      await r.enter(900);
      await r.type('Welcome back, {name}!');
      await r.enter(900);
      await r.type('Bon retour, {name} !');
      await r.enter();
      await r.snap(2500);
      await r.enter(800);
    });
  });

  test('translate', () async {
    await _demo('translate', (r) async {
      await r.char('t', 1200);
      await r.enter(1200); // fr
      await r.type('Se connecter');
      await r.enter(900);
      await r.type('Mot de passe oublié ?');
      await r.enter();
      await r.snap(2500);
      await r.enter(800);
    });
  });

  test('check', () async {
    await _demo('check', (r) async {
      await r.char('c', 2500);
      await r.enter(1200);
      await r.type('Se connecter');
      await r.enter(2000);
      await r.esc(1200);
    });
  });

  test('hardcoded', () async {
    await _demo('hardcoded', (r) async {
      await r.char('h', 2200);
      await r.down(400);
      await r.enter(1200); // "Signed in as $name"
      await r.down(400); // home → … pick module
      await r.down(400);
      await r.enter(1200);
      await r.enter(2500); // accept suggested key → preview
      await r.enter(); // Extract
      await r.snap(2000);
      await r.esc(800);
    });
  });
}
