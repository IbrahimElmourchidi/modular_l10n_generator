import 'dart:io';

import 'package:modular_l10n_generator/src/cli/runner.dart';

Future<void> main(List<String> args) async {
  exitCode = await runCli(args);
}
