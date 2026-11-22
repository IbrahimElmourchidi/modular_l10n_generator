---
title: Using the generated code
description: Set up MaterialApp, read texts in widgets and outside them, and change the locale.
---

The generator writes into `lib/generated/modular_l10n/` (change it with [`output_dir`](/reference/configuration/)). Import one file:

```dart
import 'generated/modular_l10n/l10n.dart';
```

The examples use the default class name, `ML`. Change it with [`class_name`](/reference/configuration/).

## Set up the app

```dart
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
```

The Global delegates come from `package:flutter_localizations/flutter_localizations.dart`. They translate Flutter's own widgets, such as date pickers and the back button tooltip.

## In widgets

```dart
final l10n = ML.of(context);

Text(l10n.auth.emailLabel);
Text(l10n.home.cartItems(3));
Text(l10n.home.lastSeen(DateTime.now()));
```

`ML.maybeOf(context)` returns `null` instead of throwing when the delegate is not loaded, for widgets that can also be used outside the app.

## Outside widgets

In services, view models, cubits and the like, after the delegate has loaded once:

```dart
final label = ML.current.auth.emailLabel;
```

`ML.current` is the most recently loaded locale.

## Change the locale

Pass a locale to `MaterialApp` and rebuild:

```dart
MaterialApp(
  locale: const Locale('fr'),
  // ...
);
```

When `locale` is `null`, Flutter uses the device's languages and picks the closest supported one: an exact match first, then the same language and country, then the same language. A device set to `fr_CA` gets `fr`.

To load a locale without a widget tree, for example in a test:

```dart
final fr = await ML.load(const Locale('fr'));
fr.auth.emailLabel; // "E-mail"
```

## Missing translations

When a translation is missing or empty, that key shows the default locale's text. The app never shows an empty string or a key name. `check` lists these keys so you can fill them in.

## Module access

With the default `module_access: part`, modules are only reachable through `ML`. That keeps one entry point and lets `check` flag code that imports a module file directly. With `module_access: library`, each module file is its own library and can be imported on its own.

## Commit the generated code?

Either works:

- **Commit it**: the app builds without running the generator, and code review shows text changes. Add the `git diff --exit-code` step from [CI](/guides/ci/) to catch forgotten regenerations.
- **Ignore it**: add `lib/generated/modular_l10n/` to `.gitignore` and run `dart run modular_l10n_generator` before `flutter build` in CI.
