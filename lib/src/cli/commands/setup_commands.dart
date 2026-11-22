/// `init` and `create-module`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../config.dart';
import '../../ops/arb_file.dart';
import '../../ops/module_ops.dart';
import '../../ops/project.dart';
import '../project_command.dart';

class InitCommand extends ProjectCommand {
  InitCommand() : super(regenerates: true) {
    argParser
      ..addOption('default-locale', help: 'Template locale.', valueHelp: 'en')
      ..addOption('module', help: 'Name of the first module (snake_case).')
      ..addOption('dir',
          help: 'Folder for the first module, relative to the current '
              'directory. Its ARB files go in <dir>/l10n/.')
      ..addOption('class-name', help: 'Generated class name.', valueHelp: 'ML')
      ..addFlag('yes',
          abbr: 'y',
          negatable: false,
          help: 'Re-initialize without asking when already configured.');
  }

  @override
  String get name => 'init';

  @override
  String get description =>
      'Set up Modular L10n: add the modular_l10n section to pubspec.yaml and '
      'create the first module.';

  @override
  int execute() {
    final root = rootPath;
    if (PubspecReader(root).readConfig() != null &&
        !confirmed('Modular L10n is already configured in pubspec.yaml. '
            'Re-initialize?')) {
      return 0;
    }
    final locale = option('default-locale',
        question: 'Default locale',
        defaultValue: 'en',
        validate: validateLocale);
    final module = option('module',
        question: 'First module name (snake_case)',
        defaultValue: 'app',
        validate: validateModuleName);
    final dir = option('dir',
        question: 'Folder for the module',
        defaultValue: p.relative(p.join(root, 'lib', 'features', module)));
    final className = option('class-name',
        question: 'Generated class name',
        defaultValue: 'ML',
        validate: validateClassName);

    final result = initProject(
      root,
      defaultLocale: locale,
      moduleName: module,
      moduleFolder: dir,
      className: className,
    );
    final code = finish(result, summary: 'Modular L10n is set up.');
    if (code == 0) {
      logger.summary('''

Next steps:
  1. Add the dependencies:  flutter pub add intl flutter_localizations --sdk=flutter
  2. In MaterialApp:        localizationsDelegates: [$className.delegate, ...]
                            supportedLocales: $className.supportedLocales
  3. In widgets:            $className.of(context).${toCamel(module)}.${starterKey(module)}''');
    }
    return code;
  }
}

String toCamel(String module) {
  final parts = module.split('_').where((s) => s.isNotEmpty).toList();
  return parts.first +
      parts.skip(1).map((s) => s[0].toUpperCase() + s.substring(1)).join();
}

class CreateModuleCommand extends ProjectCommand {
  CreateModuleCommand() : super(regenerates: true) {
    argParser
      ..addOption('dir',
          help: 'Feature folder, relative to the current directory. The ARB '
              'files go in <dir>/l10n/.')
      ..addOption('name',
          help: 'Module name (snake_case). Defaults to the folder name.')
      ..addOption('locales',
          help: 'Comma-separated locales. Defaults to the project\'s locales.')
      ..addFlag('empty',
          negatable: false, help: 'Do not add the <module>Title starter key.')
      ..addFlag('overwrite',
          negatable: false, help: 'Replace ARB files that already exist.');
  }

  @override
  String get name => 'create-module';

  @override
  List<String> get aliases => const ['module'];

  @override
  String get description =>
      'Create a module: an l10n/ folder with one ARB file per locale. '
      'Also adds missing locale files to an existing module folder.';

  @override
  int execute() {
    final project = loadProject();
    final dir = option('dir',
        question: 'Feature folder (the l10n/ folder is created inside it)',
        validate: (v) => v.trim().isEmpty ? 'Enter a folder.' : null);
    final folder = p.normalize(p.absolute(dir));
    final existing = _moduleIn(project, folder);
    final name = option('name',
        question: 'Module name',
        defaultValue: existing ?? suggestModuleName(folder),
        validate: validateModuleName);
    final defaultLocales =
        project.locales.isEmpty ? [project.defaultLocale] : project.locales;
    final localesText = option('locales',
        question: 'Locales',
        defaultValue: defaultLocales.join(', '), validate: (v) {
      try {
        parseLocaleList(v);
        return null;
      } on OpException catch (e) {
        return e.message;
      }
    });

    if (!Directory(folder).existsSync()) {
      logger.verbose('Creating ${p.relative(folder)}');
    }
    final result = createModule(
      project,
      folder: folder,
      name: name,
      locales: parseLocaleList(localesText),
      empty: argResults!['empty'] == true,
      overwrite: argResults!['overwrite'] == true,
    );
    return finish(result,
        summary: result.created.isEmpty
            ? null
            : 'Module "$name" has ${result.created.length} new ARB file(s).');
  }

  String? _moduleIn(Project project, String folder) {
    for (final m in project.modules) {
      if (p.equals(project.l10nDir(m), p.join(folder, 'l10n'))) return m.name;
    }
    return null;
  }
}
