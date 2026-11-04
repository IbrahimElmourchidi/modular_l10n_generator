/// Locks byte-for-byte parity with the VS Code extension.
///
/// `fixtures/parity/expected_*` was produced by the extension's TypeScript
/// generator (4.2.0) from `fixtures/parity/project`, which is the extension's
/// ICU fixture corpus plus modules covering collation order, formatting
/// metadata, and rejected inputs. Any difference here means the two tools
/// would emit different code for the same project.
library;

import 'dart:io';

import 'package:modular_l10n_generator/modular_l10n_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final fixtures = p.join('test', 'fixtures', 'parity');

  for (final mode in ['part', 'library']) {
    test('output matches the VS Code extension ($mode)', () {
      final root = tempProject();
      copyDirectory(Directory(p.join(fixtures, 'project')), Directory(root));
      File(p.join(root, 'pubspec.yaml')).writeAsStringSync(
        'name: parity_app\nmodular_l10n:\n  module_access: $mode\n',
      );

      final err = StringBuffer();
      final result = runGeneration(
        rootPath: root,
        logger: Logger(out: StringBuffer(), err: err),
        today: DateTime.utc(2026, 11, 4),
      );
      expect(result.success, isTrue);

      final expectedDir = Directory(p.join(fixtures, 'expected_$mode'));
      final actualDir =
          Directory(p.join(root, 'lib', 'generated', 'modular_l10n'));
      // Goldens carry a `.golden` suffix so analyzers and formatters skip
      // them: the corpus deliberately includes messages that do not compile.
      final expected = [
        for (final golden in listRelative(expectedDir))
          golden.substring(0, golden.length - '.golden'.length),
      ];
      expect(listRelative(actualDir), expected);
      for (final relative in expected) {
        expect(
          File(p.join(actualDir.path, relative)).readAsStringSync(),
          File(p.join(expectedDir.path, '$relative.golden')).readAsStringSync(),
          reason: relative,
        );
      }

      final expectedWarnings = File(p.join(fixtures, 'expected_warnings.txt'))
          .readAsLinesSync()
          .where((l) => l.isNotEmpty)
          .map((l) => l.replaceFirst('❌ ', ''))
          .toList()
        ..sort();
      final actualWarnings = err
          .toString()
          .split('\n')
          .where((l) => l.isNotEmpty)
          .map((l) => l.replaceFirst('warning: ', ''))
          .toList()
        ..sort();
      expect(actualWarnings, expectedWarnings);
    });
  }
}
