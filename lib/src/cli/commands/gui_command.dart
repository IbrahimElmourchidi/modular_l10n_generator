/// `gui`: the interactive terminal app.
library;

import 'dart:io';

import '../../tui/app.dart';
import '../project_command.dart';

class GuiCommand extends ProjectCommand {
  @override
  String get name => 'gui';

  @override
  List<String> get aliases => const ['ui'];

  @override
  String get description =>
      'Open the interactive terminal app: every action in one place, with '
      'folder browsing and guided steps.';

  @override
  Future<int> execute() async {
    if (!stdout.hasTerminal || !stdin.hasTerminal) {
      logger.error('The GUI needs an interactive terminal. In scripts and CI, '
          'use the commands instead (see --help).');
      return 1;
    }
    await runGui(rootPath);
    return 0;
  }
}
