---
title: Library API
description: Use the generator and every command's operation from Dart build scripts.
---

Everything the commands do is also a Dart function, for build scripts and other tools. The library does not include the terminal GUI.

```dart
import 'package:modular_l10n_generator/modular_l10n_generator.dart';
```

## Generate

```dart
final result = runGeneration(rootPath: '.', logger: Logger());
if (!result.success) exit(1);
print('${result.keyCount} keys in ${result.moduleCount} modules');
```

`overrides: ConfigOverrides(...)` overrides `pubspec.yaml` settings for this run, like the command-line flags.

## Work on a project

`Project.load` reads the configuration and scans the modules once. Every operation takes it and returns an `OpResult` listing the files it created, changed, deleted or skipped. Operations throw `OpException` with a readable message when something is wrong.

```dart
final project = Project.load('.');

createModule(project, folder: 'lib/features/cart', name: 'cart', locales: ['en', 'fr']);
addKey(project.reload(), module: 'cart', key: 'checkout',
    values: {'en': 'Checkout', 'fr': 'Commander'});
addLocale(project.reload(), 'de');

final issues = checkProject(project.reload());
for (final issue in issues) {
  print('${issue.severity.name}: ${issue.message}');
}
```

Call `project.reload()` after an operation that changes files, so the next one sees them.

## Available operations

| Area | Functions |
|---|---|
| Setup | `initProject`, `createModule`, `diagnoseProject` |
| Keys | `addKey`, `moduleKeys`, `setTranslation`, `untranslatedKeys`, `renameKey` |
| Locales | `addLocale`, `removeLocale`, `generatePseudoLocale` |
| Quality | `checkProject`, `findUnusedKeys`, `removeKeys`, `sortArbFiles` |
| Code | `scanHardcodedStrings`, `planExtract`, `extractString` |
| Exchange | `exportTranslations`, `importTranslations`, `findFlutterIntlArbs`, `migrateFromFlutterIntl` |
| Lower level | `ModuleScanner`, `ArbParser`, `DartGenerator`, `parseIcu`, `ArbWatcher` |

The API reference on [pub.dev](https://pub.dev/documentation/modular_l10n_generator/latest/) documents every parameter.
