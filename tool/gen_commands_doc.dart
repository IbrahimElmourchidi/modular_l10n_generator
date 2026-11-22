// Writes the docs site's command reference from the real argument parsers,
// so it always matches the code.
//
//   dart run tool/gen_commands_doc.dart
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:modular_l10n_generator/src/cli/runner.dart';

const _out = 'website/src/content/docs/reference/commands.md';

/// Options every command takes; documented once at the top.
const _common = {'help', 'root', 'verbose', 'quiet', 'generate', 'force'};

const _groups = <String, List<String>>{
  'Project': ['generate', 'watch', 'gui', 'init', 'doctor'],
  'Modules and keys': ['create-module', 'add-key', 'rename-key'],
  'Locales': ['add-locale', 'remove-locale', 'pseudo-locale'],
  'Quality': ['check', 'sort', 'unused', 'hardcoded', 'extract'],
  'Exchange': ['export', 'import', 'migrate'],
};

const _examples = <String, List<(String, String)>>{
  'generate': [
    ('Generate once (also what plain `modular_l10n_generator` does)', ''),
    ('Fail CI on warnings', '--fatal-warnings'),
    (
      'Try a different class name without editing pubspec.yaml',
      '--class-name L10n'
    ),
  ],
  'watch': [('Regenerate on every ARB save', '')],
  'gui': [('Open the terminal app', '')],
  'init': [
    ('Ask for each value', ''),
    (
      'No questions (scripts)',
      '--default-locale en --module app --dir lib/app --class-name ML'
    ),
  ],
  'doctor': [('Report', ''), ('Apply the pubspec.yaml fixes', '--fix')],
  'create-module': [
    ('Module named after the folder', '--dir lib/features/auth'),
    (
      'Pick the name and locales',
      '--dir lib/features/auth --name auth --locales en,ar,fr'
    ),
  ],
  'add-key': [
    ('Plain text', '-m auth -k emailLabel --value en=Email --value fr=E-mail'),
    (
      'With a placeholder and a description',
      "-m home -k cartItems --value 'en={count, plural, =0{Empty} one{1 item} other{{count} items}}' --placeholder count:int --description 'Cart badge'"
    ),
  ],
  'rename-key': [
    ('Preview', '-m auth --from emailLabel --to email --dry-run'),
    (
      'Rename in ARB files and Dart code',
      '-m auth --from emailLabel --to email'
    ),
  ],
  'add-locale': [
    ('Add French to every module', 'fr'),
    ('With a region', 'pt_BR')
  ],
  'remove-locale': [('Remove without asking (scripts)', 'fr --yes')],
  'pseudo-locale': [
    ('Default: en_XA, 30% longer', ''),
    ('Longer text', '--locale en_XB --expansion 0.5'),
  ],
  'check': [
    ('Errors only fail the run', ''),
    (
      'Everything, and fail on warnings too',
      '--unused --hardcoded --hints --fatal-warnings'
    ),
  ],
  'sort': [('Sort every ARB file', ''), ('CI: fail when unsorted', '--check')],
  'unused': [('List', ''), ('Delete them from every locale', '--remove --yes')],
  'hardcoded': [('List UI strings in lib/', '')],
  'extract': [
    (
      'Move the string at line 12, column 15 into the profile module',
      '--file lib/features/profile/profile_screen.dart --line 12 --column 15 -m profile'
    ),
  ],
  'export': [
    ('Spreadsheet', '-o translations.csv'),
    ('One module, for a translation tool', '-m auth -o auth.xlf'),
  ],
  'import': [
    ('Preview', 'translations.csv --dry-run'),
    ('Apply', 'translations.csv')
  ],
  'migrate': [
    ('Everything into one module', '--mode single --module app --dir lib/app'),
    ('One module per key prefix', '--mode prefix --base-dir lib/features'),
  ],
};

String _flag(Option o) {
  final name =
      o.negatable == true && o.isFlag ? '--[no-]${o.name}' : '--${o.name}';
  final value = o.isFlag ? '' : '=<${o.valueHelp ?? 'value'}>';
  return '`${o.abbr == null ? '' : '-${o.abbr}, '}$name$value`';
}

String _cell(String s) => s.replaceAll('|', r'\|').replaceAll('\n', ' ');

String _describe(Option o) {
  final parts = <String>[_cell(o.help ?? '')];
  if (o.allowedHelp != null) {
    parts.add(o.allowedHelp!.entries
        .map((e) => '`${e.key}`: ${_cell(e.value)}')
        .join('; '));
  } else if (o.allowed != null) {
    parts.add('One of ${o.allowed!.map((a) => '`$a`').join(', ')}.');
  }
  if (o.isMultiple) parts.add('Repeatable.');
  final d = o.defaultsTo;
  if (o.isFlag) {
    if (d == true) parts.add('On by default.');
  } else if (d != null && !(d is List && d.isEmpty)) {
    parts.add('Default: `$d`.');
  }
  return parts.where((p) => p.isNotEmpty).join(' ');
}

void main() {
  final runner = buildCommandRunner();
  final commands = runner.commands;
  final listed = _groups.values.expand((c) => c).toSet();
  final missing = commands.entries
      .where((e) =>
          e.key == e.value.name && e.key != 'help' && !listed.contains(e.key))
      .map((e) => e.key);
  if (missing.isNotEmpty) {
    stderr.writeln('Add these commands to _groups: ${missing.join(', ')}');
    exit(1);
  }

  final b = StringBuffer()
    ..writeln('---')
    ..writeln('title: Commands')
    ..writeln('description: Every command, its options and examples.')
    ..writeln('---')
    ..writeln()
    ..writeln(
        '<!-- Generated by tool/gen_commands_doc.dart from the real argument parsers. Do not edit. -->')
    ..writeln()
    ..writeln(
        'Every action in the [terminal GUI](/gui/) is also a command, for scripts, CI and IDE tools. '
        'The examples use the short `ml10n` name; inside a project you can always write '
        '`dart run modular_l10n_generator` instead.')
    ..writeln()
    ..writeln(
        'When a required value is missing and you are in a terminal, the command asks for it. '
        'In scripts and CI it stops with exit code `64` instead, so nothing ever waits for input.')
    ..writeln()
    ..writeln('## Options every command takes')
    ..writeln()
    ..writeln('| Option | Meaning |')
    ..writeln('|---|---|')
    ..writeln(
        '| `--root=<dir>` | Project directory. Defaults to the nearest folder with a `pubspec.yaml`, starting from the current one. |')
    ..writeln('| `-v, --verbose` | Show progress detail. |')
    ..writeln('| `-q, --quiet` | Only show errors. |')
    ..writeln(
        '| `--[no-]generate` | Commands that change ARB files regenerate the Dart code afterwards. `--no-generate` skips that. |')
    ..writeln(
        '| `--force` | Generate even when the settings collide with Flutter Intl. |')
    ..writeln('| `-h, --help` | Print the command\'s usage. |')
    ..writeln()
    ..writeln('## Exit codes')
    ..writeln()
    ..writeln('| Code | Meaning |')
    ..writeln('|---|---|')
    ..writeln('| `0` | Success. |')
    ..writeln(
        '| `1` | The command failed: generation errors, problems found by `check`, unsorted files under `sort --check`, or warnings under `--fatal-warnings`. |')
    ..writeln(
        '| `64` | Usage error: unknown option, invalid value, or a missing value when not in a terminal. |')
    ..writeln();

  for (final MapEntry(key: group, value: names) in _groups.entries) {
    b
      ..writeln('## $group')
      ..writeln();
    for (final name in names) {
      final Command<int> c = commands[name]!;
      final options = c.argParser.options.values
          .where((o) => !o.hide && !_common.contains(o.name))
          .toList();
      final invocation =
          c.invocation.replaceFirst('modular_l10n_generator', 'ml10n');
      b
        ..writeln('### `$name`')
        ..writeln()
        ..writeln(c.description)
        ..writeln();
      if (c.aliases.isNotEmpty) {
        b
          ..writeln('Alias: ${c.aliases.map((a) => '`$a`').join(', ')}.')
          ..writeln();
      }
      b
        ..writeln('```sh')
        ..writeln(invocation)
        ..writeln('```')
        ..writeln();
      if (c.argParser.options.containsKey('generate')) {
        b
          ..writeln(
              'Regenerates the Dart code afterwards (`--no-generate` to skip).')
          ..writeln();
      }
      if (options.isNotEmpty) {
        b
          ..writeln('| Option | Meaning |')
          ..writeln('|---|---|');
        for (final o in options) {
          b.writeln('| ${_flag(o)} | ${_describe(o)} |');
        }
        b.writeln();
      }
      final examples = _examples[name] ?? const [];
      if (examples.isNotEmpty) {
        b.writeln('```sh');
        for (final (i, (title, args)) in examples.indexed) {
          if (i > 0) b.writeln();
          b
            ..writeln('# $title')
            ..writeln('ml10n $name${args.isEmpty ? '' : ' $args'}');
        }
        b
          ..writeln('```')
          ..writeln();
      }
    }
  }

  File(_out)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(b.toString());
  stdout.writeln('Wrote $_out');
}
