import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../config.dart';
import '../generate.dart';
import '../logger.dart';
import '../version.dart';
import '../watch.dart';
import 'commands/edit_commands.dart';
import 'commands/exchange_commands.dart';
import 'commands/gui_command.dart';
import 'commands/quality_commands.dart';
import 'commands/setup_commands.dart';

const _executable = 'modular_l10n_generator';

/// Run the command line with [args]. Returns the process exit code:
/// 0 on success, 1 when generation failed (or warned under
/// `--fatal-warnings`), 64 for a usage error.
Future<int> runCli(List<String> args) async {
  final runner = buildCommandRunner();
  try {
    final topLevel = runner.parse(_withDefaultCommand(args, runner));
    if (topLevel['version'] == true) {
      stdout.writeln('$_executable $packageVersion');
      return 0;
    }
    return await runner.runCommand(topLevel) ?? 0;
  } on UsageException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln()
      ..writeln(e.usage);
    return 64;
  }
}

/// Every command and option, without running anything. The docs site's
/// command reference is generated from this (tool/gen_commands_doc.dart).
CommandRunner<int> buildCommandRunner() => CommandRunner<int>(
      _executable,
      'Generate a type-safe, modular Flutter localization API from ARB files.\n\n'
      'Configuration comes from the modular_l10n: section of pubspec.yaml; '
      'flags override it.\nRunning with no command is the same as "generate".',
    )
      ..argParser
          .addFlag('version', negatable: false, help: 'Print the version.')
      ..addCommand(_GenerateCommand())
      ..addCommand(_WatchCommand())
      ..addCommand(InitCommand())
      ..addCommand(CreateModuleCommand())
      ..addCommand(AddKeyCommand())
      ..addCommand(AddLocaleCommand())
      ..addCommand(RemoveLocaleCommand())
      ..addCommand(RenameKeyCommand())
      ..addCommand(SortCommand())
      ..addCommand(CheckCommand())
      ..addCommand(UnusedCommand())
      ..addCommand(DoctorCommand())
      ..addCommand(PseudoLocaleCommand())
      ..addCommand(ExportCommand())
      ..addCommand(ImportCommand())
      ..addCommand(MigrateCommand())
      ..addCommand(HardcodedCommand())
      ..addCommand(ExtractCommand())
      ..addCommand(GuiCommand());

/// `generate` is the default command: no arguments, or only options.
List<String> _withDefaultCommand(List<String> args, CommandRunner<int> runner) {
  if (args.isEmpty) return ['generate'];
  final first = args.first;
  if (runner.commands.containsKey(first)) return args;
  if (first == '--help' ||
      first == '-h' ||
      first == '--version' ||
      first == 'help') {
    return args;
  }
  return first.startsWith('-') ? ['generate', ...args] : args;
}

abstract class _BaseCommand extends Command<int> {
  _BaseCommand() {
    argParser
      ..addOption('root',
          help: 'Project directory. Defaults to the nearest directory with a '
              'pubspec.yaml, starting from the current one.')
      ..addOption('class-name',
          help: 'Name of the generated entry-point class.')
      ..addOption('output-dir',
          help: 'Output directory, relative to the project root.')
      ..addOption('default-locale', help: 'Template locale (for example en).')
      ..addOption('arb-pattern',
          help: 'Glob for ARB files, relative to the project root.')
      ..addOption('module-access',
          allowed: ['part', 'library'],
          help: 'part: modules are reachable only through the entry point. '
              'library: each module file can be imported directly.')
      ..addFlag('combined-arb',
          defaultsTo: null, help: 'Write one merged ARB file per locale.')
      ..addFlag('deferred-loading',
          defaultsTo: null, help: 'Load locale tables lazily.')
      ..addOption('log-level',
          allowed: ['silent', 'error', 'warning', 'verbose'])
      ..addFlag('verbose',
          abbr: 'v', negatable: false, help: 'Same as --log-level verbose.')
      ..addFlag('quiet',
          abbr: 'q', negatable: false, help: 'Same as --log-level error.')
      ..addFlag('force',
          negatable: false,
          help: 'Generate even when the settings collide with Flutter Intl.')
      ..addFlag('fatal-warnings',
          negatable: false,
          help: 'Exit with code 1 when there are warnings (for CI).');
  }

  ArgResults get _args => argResults!;

  String get rootPath {
    final explicit = _args['root'] as String?;
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

  ConfigOverrides get overrides {
    LogLevel? level = LogLevel.tryParse(_args['log-level']);
    if (_args['verbose'] == true) level = LogLevel.verbose;
    if (_args['quiet'] == true) level = LogLevel.error;
    return ConfigOverrides(
      className: _args['class-name'] as String?,
      outputDir: _args['output-dir'] as String?,
      defaultLocale: _args['default-locale'] as String?,
      arbFilePattern: _args['arb-pattern'] as String?,
      moduleAccess: ModuleAccess.tryParse(_args['module-access']),
      generateCombinedArb: _args['combined-arb'] as bool?,
      useDeferredLoading: _args['deferred-loading'] as bool?,
      logLevel: level,
    );
  }

  bool get force => _args['force'] == true;
  bool get fatalWarnings => _args['fatal-warnings'] == true;

  int exitCodeFor(GenerationResult result) {
    if (!result.success) return 1;
    if (fatalWarnings && result.warningCount > 0) return 1;
    return 0;
  }
}

class _GenerateCommand extends _BaseCommand {
  @override
  String get name => 'generate';

  @override
  String get description => 'Generate the localization code once.';

  @override
  int run() {
    final result = runGeneration(
      rootPath: rootPath,
      logger: Logger(),
      overrides: overrides,
      force: force,
    );
    return exitCodeFor(result);
  }
}

class _WatchCommand extends _BaseCommand {
  @override
  String get name => 'watch';

  @override
  String get description =>
      'Generate, then regenerate whenever an ARB file or pubspec.yaml changes.';

  @override
  Future<int> run() async {
    final root = rootPath;
    final cliOverrides = overrides;
    final logger = Logger();

    void generate() => runGeneration(
          rootPath: root,
          logger: logger,
          overrides: cliOverrides,
          force: force,
        );

    generate();

    final watcher = ArbWatcher(
      rootPath: root,
      patternOf: () => currentArbPattern(root, cliOverrides.arbFilePattern),
      onChange: generate,
      trace: logger.verbose,
    );
    await watcher.start();
    logger.summary('Watching for changes. Press Ctrl+C to stop.');

    final signals = [
      ProcessSignal.sigint.watch(),
      if (!Platform.isWindows) ProcessSignal.sigterm.watch(),
    ].map((s) => s.listen((_) => watcher.stop())).toList();

    await watcher.done;
    for (final subscription in signals) {
      await subscription.cancel();
    }
    return 0;
  }
}
