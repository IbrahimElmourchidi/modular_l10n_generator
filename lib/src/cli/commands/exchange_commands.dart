/// `pseudo-locale`, `export`, `import`, `migrate`, `hardcoded` and `extract`.
library;

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../config.dart';
import '../../ops/arb_file.dart';
import '../../ops/exchange_ops.dart';
import '../../ops/project.dart';
import '../../ops/scan_ops.dart';
import '../project_command.dart';

class PseudoLocaleCommand extends ProjectCommand {
  PseudoLocaleCommand() : super(regenerates: true) {
    argParser
      ..addOption('locale',
          abbr: 'l', help: 'Pseudo-locale code.', defaultsTo: 'en_XA')
      ..addOption('expansion',
          help: 'Extra length as a fraction (0.3 = 30% longer, like German).',
          defaultsTo: '0.3');
  }

  @override
  String get name => 'pseudo-locale';

  @override
  String get description =>
      'Generate an accented, lengthened copy of the default locale to test '
      'layouts and spot hardcoded text.';

  @override
  int execute() {
    final project = loadProject();
    final locale = argResults!['locale'] as String;
    final expansion = double.tryParse(argResults!['expansion'] as String);
    if (expansion == null || expansion < 0 || expansion > 3) {
      throw UsageException(
          '--expansion must be a number between 0 and 3.', usage);
    }
    final result =
        generatePseudoLocale(project, locale: locale, expansion: expansion);
    return finish(result,
        summary:
            'Run the app with Locale(\'${normalizeLocale(locale).split('_').join("', '")}\') to see it.');
  }
}

class ExportCommand extends ProjectCommand {
  ExportCommand() {
    argParser
      ..addOption('output',
          abbr: 'o',
          help: 'File to write; .csv or .xlf/.xliff decides the format.',
          defaultsTo: 'translations.csv')
      ..addOption('format',
          allowed: ['csv', 'xliff'], help: 'Override the format.')
      ..addOption('module', abbr: 'm', help: 'Only this module.');
  }

  @override
  String get name => 'export';

  @override
  String get description =>
      'Export translations to CSV (for spreadsheets) or XLIFF 1.2 (for '
      'translation tools).';

  @override
  int execute() {
    final project = loadProject();
    final output = p.absolute(argResults!['output'] as String);
    final format = switch (argResults!['format']) {
      'csv' => ExchangeFormat.csv,
      'xliff' => ExchangeFormat.xliff,
      _ => null,
    };
    final count = exportTranslations(project,
        outputPath: output,
        format: format,
        module: argResults!['module'] as String?);
    logger.summary('Exported $count key(s) to ${p.relative(output)}.');
    return 0;
  }
}

class ImportCommand extends ProjectCommand {
  ImportCommand() : super(regenerates: true) {
    argParser.addFlag('dry-run',
        negatable: false, help: 'Show the changes without writing them.');
  }

  @override
  String get name => 'import';

  @override
  String get description =>
      'Import translations from a CSV or XLIFF file made by "export". Only '
      'existing keys are filled; empty cells are ignored.';

  @override
  String get invocation => '${runner!.executableName} $name <file>';

  @override
  int execute() {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      throw UsageException('Give one file to import.', usage);
    }
    final project = loadProject();
    final dryRun = argResults!['dry-run'] == true;
    final result = importTranslations(project, rest.single, dryRun: dryRun);
    for (final c in result.changes) {
      logger.verbose('  ${c.module}.${c.key} [${c.locale}]: "${c.newValue}"');
    }
    for (final s in result.skipped) {
      logger.warn('skipped $s');
    }
    final summary = '${dryRun ? 'Would import' : 'Imported'} '
        '${result.changes.length} translation(s).';
    if (dryRun) {
      logger.summary(summary);
      return 0;
    }
    return finish(result.files, summary: summary);
  }
}

class MigrateCommand extends ProjectCommand {
  MigrateCommand() : super(regenerates: true) {
    argParser
      ..addOption('mode', allowed: [
        'single',
        'prefix'
      ], allowedHelp: {
        'single': 'Every key into one module.',
        'prefix': 'Split keys by camelCase prefix (authLogin → auth).',
      })
      ..addOption('from',
          help: 'Folder with the intl_*.arb files.', defaultsTo: 'lib/l10n')
      ..addOption('module', help: 'Module name (single mode).')
      ..addOption('dir', help: 'Module folder (single mode).')
      ..addOption('base-dir',
          help: 'Folder that receives one sub-folder per prefix (prefix mode).',
          defaultsTo: 'lib/features')
      ..addFlag('overwrite',
          negatable: false, help: 'Replace existing module files.')
      ..addFlag('yes', abbr: 'y', negatable: false, help: 'Do not ask.');
  }

  @override
  String get name => 'migrate';

  @override
  String get description => 'Move Flutter Intl intl_*.arb files into modules.';

  @override
  int execute() {
    final project = loadProject();
    final files =
        findFlutterIntlArbs(rootPath, dir: argResults!['from'] as String);
    if (files.isEmpty) {
      throw OpException('No intl_*.arb files in ${argResults!['from']}.');
    }
    logger.summary('Found ${files.length} Flutter Intl file(s): '
        '${files.map((f) => f.locale).join(', ')}');
    final mode = choice('mode',
        question: 'How should the keys be organised?',
        choices: ['single', 'prefix'],
        defaultValue: 'single');
    if (mode == 'single') {
      final module = option('module',
          question: 'Module name',
          defaultValue: 'app',
          validate: validateModuleName);
      final dir = option('dir',
          question: 'Module folder',
          defaultValue:
              p.relative(p.join(rootPath, 'lib', 'features', module)));
      return finish(migrateFromFlutterIntl(project,
          files: files,
          module: module,
          folder: dir,
          overwrite: argResults!['overwrite'] == true));
    }
    final prefixes = countPrefixes(files);
    logger.summary(
        'Modules: ${prefixes.entries.map((e) => '${e.key} (${e.value})').join(', ')}');
    if (!confirmed('Create these modules?')) return 0;
    return finish(migrateFromFlutterIntl(project,
        files: files,
        baseFolder: p.join(rootPath, argResults!['base-dir'] as String),
        overwrite: argResults!['overwrite'] == true));
  }
}

class HardcodedCommand extends ProjectCommand {
  @override
  String get name => 'hardcoded';

  @override
  String get description =>
      'List string literals in lib/ that look like UI text.';

  @override
  int execute() {
    final project = loadProject();
    final found = scanHardcodedStrings(project);
    for (final s in found) {
      logger.summary(
          '${project.relative(s.file)}:${s.line}:${s.column + 1}  ${s.literal}');
    }
    logger.summary(found.isEmpty
        ? 'No hardcoded strings found.'
        : '${found.length} hardcoded string(s). Move one into an ARB file with:\n'
            '  ${runner!.executableName} extract --file <file> --line <line> --column <column> '
            '--module <module>');
    return 0;
  }
}

class ExtractCommand extends ProjectCommand {
  ExtractCommand() : super(regenerates: true) {
    argParser
      ..addOption('file', help: 'Dart file.')
      ..addOption('line', help: 'Line of the string (1-based).')
      ..addOption('column',
          help: 'Column inside the string (1-based).', defaultsTo: null)
      ..addOption('module', abbr: 'm', help: 'Module to add the key to.')
      ..addOption('key',
          abbr: 'k', help: 'Key name. Suggested from the text when omitted.');
  }

  @override
  String get name => 'extract';

  @override
  String get description =>
      'Move a string literal into an ARB file and replace it with the '
      'generated lookup.';

  @override
  int execute() {
    final project = loadProject();
    final file = p.absolute(option('file', question: 'Dart file'));
    final line = int.tryParse(option('line', question: 'Line'));
    if (line == null) throw UsageException('--line must be a number.', usage);
    final columnText = argResults!['column'] as String?;
    final column = columnText == null ? null : int.tryParse(columnText);
    if (columnText != null && column == null) {
      throw UsageException('--column must be a number.', usage);
    }
    final plan = column != null
        ? planExtract(file, line, column - 1)
        : _onlyLiteral(file, line);
    logger.summary('Text: "${plan.arbValue}"');
    final module = choice('module',
        question: 'Module',
        choices: project.modules.map((m) => m.name).toList()..sort());
    final key = option('key',
        question: 'Key',
        defaultValue: plan.suggestedKey,
        validate: validateKeyName);
    return finish(extractString(project, plan, module: module, key: key),
        summary: 'Extracted to $module.$key.');
  }

  ExtractPlan _onlyLiteral(String file, int line) {
    final candidates = scanDartFile(file).where((s) => s.line == line).toList();
    if (candidates.length == 1) {
      return planExtract(file, line, candidates.single.column);
    }
    throw UsageException(
        candidates.isEmpty
            ? 'No UI string found on line $line; pass --column.'
            : 'Line $line has ${candidates.length} strings; pass --column.',
        usage);
  }
}
