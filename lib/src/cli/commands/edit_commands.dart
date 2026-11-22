/// `add-key`, `add-locale` and `remove-locale`.
library;

import 'package:args/command_runner.dart';

import '../../config.dart';
import '../../ops/arb_file.dart';
import '../../ops/key_ops.dart';
import '../../ops/locale_ops.dart';
import '../../ops/module_ops.dart';
import '../../ops/project.dart';
import '../project_command.dart';

class AddKeyCommand extends ProjectCommand {
  AddKeyCommand() : super(regenerates: true) {
    argParser
      ..addOption('module', abbr: 'm', help: 'Module to add the key to.')
      ..addOption('key', abbr: 'k', help: 'Key name (camelCase).')
      ..addMultiOption('value',
          help: 'A translation, as locale=text. Repeat per locale.',
          valueHelp: 'en=Hello',
          splitCommas: false)
      ..addOption('description', help: 'Description for translators.')
      ..addMultiOption('placeholder',
          help: 'A placeholder, as name or name:type. Repeatable.',
          valueHelp: 'count:int');
  }

  @override
  String get name => 'add-key';

  @override
  String get description =>
      'Add a translation key to a module, in every locale.';

  @override
  int execute() {
    final project = loadProject();
    if (project.modules.isEmpty) {
      throw OpException('There are no modules yet. Run "create-module" first.');
    }
    final module = choice('module',
        question: 'Module',
        choices: project.modules.map((m) => m.name).toList()..sort());
    final existing = moduleKeys(project, module).toSet();
    final key = option('key',
        question: 'Key (camelCase)',
        validate: (v) =>
            validateKeyName(v) ??
            (existing.contains(v) ? 'Key "$v" already exists.' : null));

    final values = <String, String>{};
    for (final entry in argResults!['value'] as List<String>) {
      final eq = entry.indexOf('=');
      if (eq <= 0) {
        throw UsageException('--value must look like locale=text.', usage);
      }
      values[normalizeLocale(entry.substring(0, eq))] = entry.substring(eq + 1);
    }
    final m = project.module(module);
    if (values.isEmpty && prompter.interactive) {
      for (final file in m.arbFiles) {
        values[file.locale] =
            prompter.ask('Text in ${file.locale}', allowEmpty: true) ?? '';
      }
    }

    final result = addKey(
      project,
      module: module,
      key: key,
      values: values,
      description: argResults!['description'] as String?,
      placeholders: [
        for (final spec in argResults!['placeholder'] as List<String>)
          PlaceholderSpec.parse(spec),
      ],
    );
    return finish(result, summary: 'Added "$key" to $module.');
  }
}

class AddLocaleCommand extends ProjectCommand {
  AddLocaleCommand() : super(regenerates: true) {
    argParser.addOption('locale', abbr: 'l', help: 'Locale to add.');
  }

  @override
  String get name => 'add-locale';

  @override
  String get description =>
      'Add a locale to every module (copies the default locale\'s keys with '
      'empty values).';

  @override
  String get invocation => '${runner!.executableName} $name <locale>';

  @override
  int execute() {
    final project = loadProject();
    final positional = argResults!.rest;
    final locale = positional.isNotEmpty
        ? positional.first
        : option('locale', question: 'Locale to add', validate: (v) {
            return validateLocale(v) ??
                (project.locales.contains(normalizeLocale(v))
                    ? 'The project already has "$v".'
                    : null);
          });
    final result = addLocale(project, locale);
    return finish(result);
  }
}

class RemoveLocaleCommand extends ProjectCommand {
  RemoveLocaleCommand() : super(regenerates: true) {
    argParser
      ..addOption('locale', abbr: 'l', help: 'Locale to remove.')
      ..addFlag('yes', abbr: 'y', negatable: false, help: 'Do not ask.');
  }

  @override
  String get name => 'remove-locale';

  @override
  String get description => 'Delete a locale\'s ARB file from every module.';

  @override
  String get invocation => '${runner!.executableName} $name <locale>';

  @override
  int execute() {
    final project = loadProject();
    final removable =
        project.locales.where((l) => l != project.defaultLocale).toList();
    if (removable.isEmpty) {
      throw OpException(
          'Only the default locale "${project.defaultLocale}" exists.');
    }
    final positional = argResults!.rest;
    final locale = positional.isNotEmpty
        ? normalizeLocale(positional.first)
        : choice('locale', question: 'Locale to remove', choices: removable);

    final files = filesForLocale(project, locale);
    if (files.isNotEmpty) {
      logger.summary('This deletes:');
      for (final f in files) {
        logger.summary('  ${project.relative(f)}');
      }
    }
    if (!confirmed('Delete ${files.length} file(s)?')) return 0;
    return finish(removeLocale(project, locale));
  }
}
