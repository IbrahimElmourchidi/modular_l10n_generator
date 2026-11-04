# Example

A Flutter app with two modules, `auth` and `home`, each with English and Arabic ARB files under `lib/features/<module>/l10n/`.

```sh
flutter pub get
dart run modular_l10n_generator    # writes lib/generated/modular_l10n/
flutter run
```

`lib/main.dart` shows the delegate setup and calls into both modules. `test/widget_test.dart` checks the rendered text in both locales, covering plurals, ordinals, currency, dates and select.
