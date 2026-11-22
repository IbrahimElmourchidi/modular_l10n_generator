/// Base class for the subcommands that change a project.
library;

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../config.dart';
import '../logger.dart';
import '../ops/project.dart';
import 'prompt.dart';

/// Shared flags (`--root`, verbosity, regeneration) and helpers: loading the
/// project, asking for missing values, reporting and regenerating.
abstract class ProjectCommand extends Command<int> {
  ProjectCommand({this.regenerates = false}) {
    argParser
      ..addOption('root',
          help: 'Project directory. Defaults to the nearest directory with a '
              'pubspec.yaml, starting from the current one.')
      ..addFlag('verbose',
          abbr: 'v', negatable: false, help: 'Show progress detail.')
      ..addFlag('quiet',
          abbr: 'q', negatable: false, help: 'Only show errors.');
    if (regenerates) {
      argParser
        ..addFlag('generate',
            defaultsTo: true, help: 'Regenerate the Dart code afterwards.')
        ..addFlag('force',
            negatable: false,
            help:
                'Regenerate even when the settings collide with Flutter Intl.');
    }
  }

  /// Whether the command changes ARB files and so regenerates afterwards.
  final bool regenerates;

  /// Replaced in tests.
  Prompter prompter = Prompter();

  Logger? _logger;
  Logger get logger =>
      _logger ??= Logger(level: _flagLevel ?? LogLevel.warning);

  LogLevel? get _flagLevel => argResults?['verbose'] == true
      ? LogLevel.verbose
      : argResults?['quiet'] == true
          ? LogLevel.error
          : null;

  String? _root;
  String get rootPath => _root ??= _findRoot();

  String _findRoot() {
    final explicit = argResults!['root'] as String?;
    if (explicit != null) {
      if (!Directory(explicit).existsSync()) {
        throw UsageException('Directory not found: $explicit', usage);
      }
      return Directory(explicit).absolute.path;
    }
    final found = findProjectRoot(Directory.current.path);
    if (found == null) {
      throw UsageException(
        'No pubspec.yaml found in ${Directory.current.path} or any parent directory.',
        usage,
      );
    }
    return found;
  }

  /// The project, with `-v`/`-q` taking precedence over `log_level`.
  Project loadProject() => Project.load(
        rootPath,
        overrides: ConfigOverrides(logLevel: _flagLevel),
      );

  /// The command's work. Throw [OpException] for a user-facing failure.
  FutureOr<int> execute();

  @override
  Future<int> run() async {
    try {
      return await execute();
    } on OpException catch (e) {
      logger.error(e.message);
      return 1;
    } on _Cancelled {
      logger.error('Cancelled.');
      return 1;
    }
  }

  /// The value of option [name], or the user's answer to [question] when it
  /// was not given. Without a terminal a missing value is a usage error.
  String option(
    String name, {
    required String question,
    String? defaultValue,
    String? Function(String value)? validate,
  }) {
    final given = argResults![name] as String?;
    if (given != null) {
      final error = validate?.call(given);
      if (error != null) throw UsageException('--$name: $error', usage);
      return given;
    }
    if (!prompter.interactive) {
      if (defaultValue != null) return defaultValue;
      throw UsageException('Missing --$name.', usage);
    }
    return prompter.ask(question,
            defaultValue: defaultValue, validate: validate) ??
        (throw _Cancelled());
  }

  /// Like [option], but picking from [choices].
  String choice(
    String name, {
    required String question,
    required List<String> choices,
    String? defaultValue,
  }) {
    final given = argResults![name] as String?;
    if (given != null) {
      if (!choices.contains(given)) {
        throw UsageException(
            '--$name must be one of: ${choices.join(', ')}.', usage);
      }
      return given;
    }
    if (choices.length == 1) return choices.single;
    if (!prompter.interactive) {
      if (defaultValue != null) return defaultValue;
      throw UsageException('Missing --$name.', usage);
    }
    return prompter.choose(question, choices, defaultValue: defaultValue) ??
        (throw _Cancelled());
  }

  /// Ask before something destructive. `--yes` (when the command defines it)
  /// answers for the user; without a terminal the answer must come from it.
  bool confirmed(String question) {
    if (argParser.options.containsKey('yes') && argResults!['yes'] == true) {
      return true;
    }
    if (!prompter.interactive) {
      throw UsageException('Pass --yes to confirm: $question', usage);
    }
    return prompter.confirm(question);
  }

  /// Report [result] and, for a command that [regenerates], regenerate when
  /// files changed. Returns the exit code.
  int finish(OpResult result, {String? summary}) {
    result.report(logger, rootPath);
    if (summary != null) logger.summary(summary);
    if (!result.touchedFiles) logger.summary('Nothing changed.');
    if (regenerates && result.touchedFiles && argResults!['generate'] == true) {
      final generation = loadProject().regenerate(
        logger,
        force: argResults!['force'] == true,
      );
      result.generation = generation;
      if (!generation.success) return 1;
    }
    return 0;
  }
}

class _Cancelled implements Exception {}
