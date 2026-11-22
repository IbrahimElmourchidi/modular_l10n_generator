/// `doctor`: is the project set up correctly, and does it collide with
/// Flutter Intl?
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../config.dart';
import 'project.dart';
import 'pubspec_writer.dart';

enum DoctorStatus { ok, warning, error }

/// One line of the doctor report.
class DoctorItem {
  const DoctorItem(this.status, this.title,
      {this.detail, this.fix, this.fixLabel});

  final DoctorStatus status;
  final String title;
  final String? detail;

  /// `modular_l10n:` values that fix the problem, when it can be fixed by
  /// editing pubspec.yaml.
  final Map<String, Object?>? fix;
  final String? fixLabel;
}

/// Check the project's setup.
List<DoctorItem> diagnoseProject(String rootPath) {
  final items = <DoctorItem>[];
  final reader = PubspecReader(rootPath);
  if (!reader.hasPubspec) {
    return [
      const DoctorItem(DoctorStatus.error, 'No pubspec.yaml',
          detail: 'Run this inside a Flutter project.'),
    ];
  }

  final ConfigOverrides? section;
  try {
    section = reader.readConfig();
  } on PubspecException catch (e) {
    return [
      DoctorItem(DoctorStatus.error, 'pubspec.yaml cannot be read',
          detail: e.message)
    ];
  }
  items.add(section == null
      ? const DoctorItem(
          DoctorStatus.warning, 'No modular_l10n section in pubspec.yaml',
          detail:
              'Defaults are used. Run "init" to write them down for the team.')
      : const DoctorItem(
          DoctorStatus.ok, 'modular_l10n section found in pubspec.yaml'));

  final Project project;
  try {
    project = Project.load(rootPath);
  } on OpException catch (e) {
    return [
      ...items,
      DoctorItem(DoctorStatus.error, 'Configuration error', detail: e.message)
    ];
  }
  final config = project.config;
  if (!config.enabled) {
    items.add(const DoctorItem(DoctorStatus.warning, 'Generation is disabled',
        detail: 'modular_l10n.enabled is false.',
        fix: {'enabled': true},
        fixLabel: 'Enable'));
  }

  // Modules.
  if (project.modules.isEmpty) {
    items.add(DoctorItem(DoctorStatus.error, 'No modules found',
        detail:
            'No ARB file matching "${config.arbFilePattern}" has both @@locale '
            'and @@context. Use "create-module" to add one.'));
  } else {
    items.add(DoctorItem(DoctorStatus.ok,
        '${project.modules.length} module(s), locales: ${project.locales.join(', ')}',
        detail: 'Default locale: ${project.defaultLocale}'));
  }
  if (project.scan.validationErrors.isNotEmpty) {
    items.add(DoctorItem(DoctorStatus.error,
        '${project.scan.validationErrors.length} invalid ARB file(s)',
        detail: project.scan.validationErrors.join('\n')));
  }
  final configured = normalizeLocale(config.defaultLocale);
  if (project.locales.isNotEmpty && !project.locales.contains(configured)) {
    items.add(DoctorItem(
        DoctorStatus.warning, 'Default locale "$configured" has no ARB files',
        detail: '"${project.defaultLocale}" is used instead.',
        fix: {'default_locale': project.defaultLocale},
        fixLabel: 'Set default_locale to ${project.defaultLocale}'));
  }

  // Dependencies the generated code imports.
  final deps = readDependencies(rootPath).dependencies;
  final missing = [
    for (final d in const ['intl', 'flutter_localizations'])
      if (!deps.contains(d)) d,
  ];
  items.add(missing.isEmpty
      ? const DoctorItem(
          DoctorStatus.ok, 'intl and flutter_localizations are dependencies')
      : DoctorItem(
          DoctorStatus.error, 'Missing dependencies: ${missing.join(', ')}',
          detail: 'The generated code imports them. Run:\n'
              '  flutter pub add intl flutter_localizations --sdk=flutter'));

  // Flutter Intl.
  final intl = reader.readFlutterIntlConfig();
  final intlArbs = Directory(p.join(rootPath, 'lib', 'l10n')).existsSync()
      ? Directory(p.join(rootPath, 'lib', 'l10n'))
          .listSync()
          .where((e) => RegExp(r'intl_.*\.arb$').hasMatch(p.basename(e.path)))
          .length
      : 0;
  if (intl == null && intlArbs == 0) {
    items.add(const DoctorItem(DoctorStatus.ok, 'Flutter Intl not used'));
  } else {
    items.add(DoctorItem(DoctorStatus.ok, 'Flutter Intl detected',
        detail: intlArbs > 0
            ? '$intlArbs intl_*.arb file(s) in lib/l10n are ignored by this tool. '
                'Use "migrate" to move them into modules.'
            : null));
    final theirClass = intl?.className ?? 'S';
    final theirDir = p.normalize(intl?.outputDir ?? 'lib/generated');
    final ours = p.normalize(config.outputDir);
    if (config.className == theirClass) {
      items.add(DoctorItem(DoctorStatus.error,
          'Class name "${config.className}" is the same as Flutter Intl\'s',
          detail: 'Both tools would generate a class with this name.',
          fix: {'class_name': 'ML'},
          fixLabel: 'Use ML'));
    }
    if (ours == theirDir) {
      items.add(DoctorItem(DoctorStatus.error,
          'Output folder "$ours" is the same as Flutter Intl\'s',
          detail: 'Both tools would write l10n.dart there.',
          fix: {'output_dir': 'lib/generated/modular_l10n'},
          fixLabel: 'Use lib/generated/modular_l10n'));
    }
  }
  return items;
}
