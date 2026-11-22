/// `sort`, `check`, `unused`, `rename-key` and `doctor`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../ops/arb_file.dart';
import '../../ops/check_ops.dart';
import '../../ops/doctor_ops.dart';
import '../../ops/key_ops.dart';
import '../../ops/maintenance_ops.dart';
import '../../ops/project.dart';
import '../../ops/pubspec_writer.dart';
import '../../ops/scan_ops.dart';
import '../project_command.dart';

class SortCommand extends ProjectCommand {
  SortCommand() : super(regenerates: true) {
    argParser
      ..addOption('module', abbr: 'm', help: 'Only this module.')
      ..addFlag('check',
          negatable: false,
          help: 'Change nothing; exit 1 when a file is not sorted (for CI).');
  }

  @override
  String get name => 'sort';

  @override
  String get description =>
      'Sort ARB keys alphabetically (@@ attributes first, each @key after its key).';

  @override
  int execute() {
    final project = loadProject();
    final check = argResults!['check'] == true;
    final result = sortArbFiles(project,
        module: argResults!['module'] as String?, dryRun: check);
    if (check) {
      for (final f in result.changed) {
        logger.error('not sorted: ${project.relative(f)}');
      }
      if (result.changed.isEmpty) logger.summary('All ARB files are sorted.');
      return result.changed.isEmpty ? 0 : 1;
    }
    return finish(result,
        summary: result.changed.isEmpty
            ? 'All ARB files are already sorted.'
            : 'Sorted ${result.changed.length} file(s).');
  }
}

class CheckCommand extends ProjectCommand {
  CheckCommand() {
    argParser
      ..addFlag('hints', negatable: false, help: 'Also show ICU hints.')
      ..addFlag('unused', negatable: false, help: 'Also list unused keys.')
      ..addFlag('hardcoded',
          negatable: false,
          help: 'Also list hardcoded UI strings in Dart code.')
      ..addFlag('fatal-warnings',
          negatable: false, help: 'Exit 1 on warnings too, not only errors.');
  }

  @override
  String get name => 'check';

  @override
  String get description =>
      'Find missing and empty translations, ICU mistakes and direct module '
      'imports. Exits 1 on errors (for CI).';

  @override
  int execute() {
    final project = loadProject();
    final issues = checkProject(project, hints: argResults!['hints'] == true);
    if (argResults!['unused'] == true) {
      for (final MapEntry(key: module, value: keys)
          in findUnusedKeys(project).entries) {
        for (final key in keys) {
          issues.add(Issue(
            severity: IssueSeverity.info,
            code: 'unused-key',
            message: '"$key" is not referenced in lib/.',
            module: module,
            key: key,
          ));
        }
      }
    }
    if (argResults!['hardcoded'] == true) {
      for (final s in scanHardcodedStrings(project)) {
        issues.add(Issue(
          severity: IssueSeverity.info,
          code: 'hardcoded-string',
          message: 'Hardcoded string ${s.literal}',
          file: s.file,
          line: s.line,
        ));
      }
    }
    printIssues(issues, project);
    final errors =
        issues.where((i) => i.severity == IssueSeverity.error).length;
    final warnings =
        issues.where((i) => i.severity == IssueSeverity.warning).length;
    if (errors > 0) return 1;
    if (warnings > 0 && argResults!['fatal-warnings'] == true) return 1;
    return 0;
  }

  void printIssues(List<Issue> issues, Project project) {
    for (final issue in issues) {
      final where = issue.file == null
          ? issue.module == null
              ? ''
              : '[${issue.module}${issue.locale == null ? '' : ' ${issue.locale}'}] '
          : '${project.relative(issue.file!)}${issue.line == null ? '' : ':${issue.line}'}: ';
      final text = '$where${issue.message} (${issue.code})';
      switch (issue.severity) {
        case IssueSeverity.error:
          logger.error(text);
        case IssueSeverity.warning:
          logger.warn(text);
        case IssueSeverity.info:
          logger.summary('info: $text');
      }
    }
    final count = <IssueSeverity, int>{};
    for (final i in issues) {
      count[i.severity] = (count[i.severity] ?? 0) + 1;
    }
    logger.summary(issues.isEmpty
        ? 'No problems found.'
        : '${count[IssueSeverity.error] ?? 0} error(s), '
            '${count[IssueSeverity.warning] ?? 0} warning(s), '
            '${count[IssueSeverity.info] ?? 0} info.');
  }
}

class UnusedCommand extends ProjectCommand {
  UnusedCommand() : super(regenerates: true) {
    argParser
      ..addFlag('remove',
          negatable: false,
          help: 'Delete the unused keys from every locale file.')
      ..addFlag('yes', abbr: 'y', negatable: false, help: 'Do not ask.');
  }

  @override
  String get name => 'unused';

  @override
  String get description =>
      'List keys no Dart file under lib/ references; --remove deletes them.';

  @override
  int execute() {
    final project = loadProject();
    final unused = findUnusedKeys(project);
    final total = unused.values.fold<int>(0, (s, k) => s + k.length);
    if (total == 0) {
      logger.summary('All keys are in use.');
      return 0;
    }
    for (final MapEntry(key: module, value: keys) in unused.entries) {
      logger.summary('$module:');
      for (final key in keys) {
        logger.summary('  $key');
      }
    }
    logger.summary('$total possibly unused key(s). Keys used dynamically show '
        'up here too; review before removing.');
    if (argResults!['remove'] != true) return 0;
    if (!confirmed('Remove $total key(s) from every locale?')) return 0;
    return finish(removeKeys(project, unused));
  }
}

class RenameKeyCommand extends ProjectCommand {
  RenameKeyCommand() : super(regenerates: true) {
    argParser
      ..addOption('module', abbr: 'm', help: 'Module of the key.')
      ..addOption('from', help: 'Current key name.')
      ..addOption('to', help: 'New key name.')
      ..addFlag('dry-run',
          negatable: false,
          help: 'Show what would change without changing it.');
  }

  @override
  String get name => 'rename-key';

  @override
  String get description =>
      'Rename a key in every locale file and update its uses in lib/.';

  @override
  int execute() {
    final project = loadProject();
    final module = choice('module',
        question: 'Module',
        choices: project.modules.map((m) => m.name).toList()..sort());
    final keys = moduleKeys(project, module);
    final from = option('from',
        question: 'Key to rename',
        validate: (v) => keys.contains(v) ? null : 'No key "$v" in $module.');
    final to = option('to',
        question: 'New name',
        validate: (v) =>
            validateKeyName(v) ??
            (keys.contains(v) ? 'Key "$v" already exists.' : null));
    final dryRun = argResults!['dry-run'] == true;
    final (:result, :dartEdits) = renameKey(project,
        module: module, oldKey: from, newKey: to, dryRun: dryRun);
    if (dryRun) {
      logger.summary('Would update:');
      for (final f in result.changed) {
        final edit = dartEdits.where((e) => e.path == f).firstOrNull;
        logger.summary('  ${project.relative(f)}'
            '${edit == null ? '' : ' (line ${edit.lines.join(', ')})'}');
      }
      return 0;
    }
    return finish(result, summary: 'Renamed "$from" to "$to".');
  }
}

class DoctorCommand extends ProjectCommand {
  DoctorCommand() {
    argParser.addFlag('fix',
        negatable: false,
        help: 'Apply the fixes that only need a pubspec.yaml change.');
  }

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check the project setup: configuration, modules, dependencies and '
      'conflicts with Flutter Intl.';

  @override
  int execute() {
    final items = diagnoseProject(rootPath);
    final useColor = stdout.supportsAnsiEscapes;
    String mark(DoctorStatus s) => switch (s) {
          DoctorStatus.ok => useColor ? '\x1B[32m✓\x1B[0m' : '[ok]',
          DoctorStatus.warning => useColor ? '\x1B[33m!\x1B[0m' : '[!]',
          DoctorStatus.error => useColor ? '\x1B[31m✗\x1B[0m' : '[x]',
        };
    for (final item in items) {
      logger.summary('${mark(item.status)} ${item.title}');
      if (item.detail != null) {
        for (final line in item.detail!.split('\n')) {
          logger.summary('    $line');
        }
      }
      if (item.fix != null) logger.summary('    fix: ${item.fixLabel}');
    }
    final fixes = items.where((i) => i.fix != null).toList();
    if (argResults!['fix'] == true && fixes.isNotEmpty) {
      updateModularConfig(rootPath, {for (final i in fixes) ...i.fix!});
      logger.summary('Updated ${p.join('pubspec.yaml')}.');
      return 0;
    }
    return items.any((i) => i.status == DoctorStatus.error) ? 1 : 0;
  }
}
