# modular_l10n_generator

Generates a type-safe, **modular** Flutter localization API from ARB files. You write ARB files per feature module, and it generates a single entry point:

```dart
Text(ML.of(context).auth.emailLabel)
Text(ML.of(context).home.unreadMessages(3))
```

It's a command-line tool, so it works from any editor (Android Studio, IntelliJ, VS Code, Vim) and in CI. Its output is byte-for-byte identical to the [Modular Flutter L10n VS Code extension](https://marketplace.visualstudio.com/items?itemName=UtaniumOrg.modular-flutter-l10n), and it reads the same `pubspec.yaml` settings. A team can mix both tools without the generated files churning.

For runtime locale helpers (RTL detection, display names, plural rules), see the companion package [`modular_l10n`](https://pub.dev/packages/modular_l10n).

## Features

- **One ARB folder per feature.** `lib/features/auth/l10n/en.arb` becomes `ML.of(context).auth`.
- **Full ICU messages.** Supports `plural` (including `=N` and `offset:`), `select`, `selectordinal`, and any nesting of them.
- **Correct ordinals.** CLDR ordinal rules are compiled in, so English gives "2nd" and "23rd" rather than intl's cardinal-based results.
- **Number and date formatting** from `@key.placeholders` metadata (`NumberFormat`, `DateFormat`).
- **Per-key fallback.** A missing or incompatible translation falls back to the template locale, with a warning.
- **Watch mode** that regenerates when an ARB file or `pubspec.yaml` changes.
- **Works alongside Flutter Intl.** `intl_*.arb` files are ignored, and conflicting settings are caught before they break the build.

## Install

```sh
flutter pub add --dev modular_l10n_generator
flutter pub add intl flutter_localizations --sdk=flutter
```

The generated code depends on `intl` and `flutter_localizations`. This package itself is only a dev dependency, so nothing from it ships in your app.

## Write ARB files

Put each module's ARB files in an `l10n/` folder. Every file needs `@@locale` and `@@context` (the module name, in snake_case):

```
lib/features/auth/l10n/en.arb
lib/features/auth/l10n/ar.arb
lib/features/home/l10n/en.arb
lib/features/home/l10n/ar.arb
```

```json
{
  "@@locale": "en",
  "@@context": "auth",
  "emailLabel": "Email",
  "welcomeBack": "Welcome back, {name}!",
  "unreadMessages": "{count, plural, =0{No new messages} one{One new message} other{# new messages}}",
  "@unreadMessages": {
    "placeholders": { "count": { "type": "int" } }
  }
}
```

Metadata (`@key`) belongs in the default-locale file. Other locales only need the translations.

## Generate

```sh
dart run modular_l10n_generator          # generate once (same as "generate")
dart run modular_l10n_generator watch    # generate, then regenerate on change
```

Run it from anywhere inside the project. It finds the nearest `pubspec.yaml`.

## Use the generated code

```dart
import 'generated/modular_l10n/l10n.dart';

MaterialApp(
  localizationsDelegates: const [
    ML.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: ML.supportedLocales,
  home: const HomeScreen(),
);

// In widgets:
Text(ML.of(context).auth.welcomeBack('Sara'));
// Outside widgets (services, cubits), after the delegate has loaded:
final label = ML.current.auth.emailLabel;
```

## Configure

All settings are optional and go in `pubspec.yaml`. These are the defaults:

```yaml
modular_l10n:
  enabled: true                         # false turns generation off
  class_name: ML
  default_locale: en                    # the template locale
  output_dir: lib/generated/modular_l10n
  arb_dir_pattern: "**/l10n/*.arb"
  generate_combined_arb: true           # one merged ARB per locale, for translation tools
  use_deferred_loading: false           # load locale tables lazily (useful on web)
  module_access: part                   # part | library
  log_level: warning                    # silent | error | warning | verbose
```

`module_access: part` makes each module file a `part` of the entry point, so `ML` is the only way in. `library` lets module files be imported directly.

Command-line flags override `pubspec.yaml`, key by key:

| Flag | Meaning |
|---|---|
| `--root <dir>` | Project directory (default: nearest `pubspec.yaml`) |
| `--class-name`, `--output-dir`, `--default-locale`, `--arb-pattern`, `--module-access` | Same as the `pubspec.yaml` keys |
| `--[no-]combined-arb`, `--[no-]deferred-loading` | Same as the `pubspec.yaml` keys |
| `-v`, `--verbose` / `-q`, `--quiet` / `--log-level` | Output detail |
| `--fatal-warnings` | Exit with code 1 if there are any warnings (for CI) |
| `--force` | Generate even when the settings collide with Flutter Intl |

Exit codes: `0` success, `1` generation failed (or warnings under `--fatal-warnings`), `64` usage error.

## Android Studio and IntelliJ

There are three ways to set it up. Pick one.

**Regenerate on save (File Watcher).** Install the *File Watchers* plugin, then go to *Settings → Tools → File Watchers → + → Custom*:

| Field | Value |
|---|---|
| File type | `JSON` (or *Any*, with the scope below) |
| Scope | a custom scope with pattern `file:*/l10n/*.arb` |
| Program | `dart` (or the full path to the Dart SDK's `bin/dart`) |
| Arguments | `run modular_l10n_generator --quiet` |
| Working directory | `$ProjectFileDir$` |
| Advanced | untick *Auto-save edited files*; tick *Trigger the watcher on external changes* |

ARB files may not be associated with JSON by default. Add `*.arb` under *Settings → Editor → File Types → JSON*.

**Run watch mode in the background.** Go to *Run → Edit Configurations → + → Shell Script*, choose *Script text*, enter `dart run modular_l10n_generator watch`, and set the working directory to the project root. Start it once per session and leave it running.

**Generate on demand (External Tool).** Go to *Settings → Tools → External Tools → +* and set Program to `dart`, Arguments to `run modular_l10n_generator`, and Working directory to `$ProjectFileDir$`. It then appears under *Tools → External Tools*, and you can give it a keyboard shortcut in *Keymap*.

## CI

```sh
dart run modular_l10n_generator --fatal-warnings
git diff --exit-code lib/generated   # fail if someone forgot to regenerate
```

## Programmatic use

The pipeline is also available as a library, for build scripts:

```dart
import 'package:modular_l10n_generator/modular_l10n_generator.dart';

final result = runGeneration(rootPath: '.', logger: Logger());
```
