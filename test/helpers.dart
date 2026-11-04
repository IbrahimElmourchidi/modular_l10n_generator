import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A fresh temporary directory, deleted after the current test.
String tempProject() {
  final dir = Directory.systemTemp.createTempSync('modular_l10n_test_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir.path;
}

/// Write [json] as an ARB file at [relative] under [root].
void writeArb(String root, String relative, Map<String, Object?> json) {
  final file = File(p.join(root, relative))..createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
}

/// Write a pubspec.yaml with an optional `modular_l10n:` section body.
void writePubspec(String root, [String section = '']) {
  File(p.join(root, 'pubspec.yaml')).writeAsStringSync(
    'name: test_app\n${section.isEmpty ? '' : 'modular_l10n:\n$section'}',
  );
}

void copyDirectory(Directory from, Directory to) {
  for (final entity in from.listSync(recursive: true)) {
    if (entity is! File) continue;
    final target =
        File(p.join(to.path, p.relative(entity.path, from: from.path)));
    target.parent.createSync(recursive: true);
    entity.copySync(target.path);
  }
}

/// Every file under [dir], as sorted posix paths relative to it.
List<String> listRelative(Directory dir) => [
      for (final entity in dir.listSync(recursive: true))
        if (entity is File)
          p.split(p.relative(entity.path, from: dir.path)).join('/'),
    ]..sort();
