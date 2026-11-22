---
title: Writing ARB files
description: File layout, ICU messages, placeholders, numbers and dates.
---

ARB (Application Resource Bundle) files are JSON files with one entry per text. The tools can create and edit them for you, but you can also edit them by hand in any editor.

## Where the files go

Each module keeps its ARB files in an `l10n/` folder, one file per locale:

```
lib/features/auth/l10n/auth_en.arb
lib/features/auth/l10n/auth_fr.arb
lib/features/home/l10n/home_en.arb
lib/features/home/l10n/home_fr.arb
```

The file name does not matter to the generator (`en.arb` works too). The tools write `<module>_<locale>.arb`, so that files from different modules have different names in editor tabs.

Every file needs two attributes:

```json
{
  "@@locale": "en",
  "@@context": "auth"
}
```

- `@@locale` is the file's language: `en`, `pt_BR`, `zh_Hans`.
- `@@context` is the module name, in snake_case. It becomes the accessor in camelCase: `user_profile` → `ML.of(context).userProfile`.

Files without both attributes are ignored. So are Flutter Intl's `intl_*.arb` files.

## Keys

Keys are camelCase and start with a lower-case letter: `emailLabel`, `signInButton`. Each key becomes a getter, or a method when the text has placeholders.

```json
{
  "@@locale": "en",
  "@@context": "auth",
  "emailLabel": "Email",
  "welcomeBack": "Welcome back, {name}!"
}
```

```dart
ML.of(context).auth.emailLabel        // String
ML.of(context).auth.welcomeBack('Sara') // String welcomeBack(Object name)
```

## Metadata

A key's metadata goes in the default-locale file only, under `@<key>`. Other locales only need the text.

```json
"welcomeBack": "Welcome back, {name}!",
"@welcomeBack": {
  "description": "Shown on the home screen after sign-in.",
  "placeholders": {
    "name": { "type": "String", "example": "Sara" }
  }
}
```

The `description` is exported for translators and appears in the generated code's doc comment.

## Placeholders

`{name}` in the text becomes a parameter. Without metadata it is `Object`. Give it a type to get type checking and formatting:

| `type` | Dart parameter | Formatting |
|---|---|---|
| `String` | `String` | none |
| `int`, `double`, `num` | that type | `format` names a `NumberFormat` constructor |
| `DateTime` | `DateTime` | `format` names a `DateFormat` constructor, or a pattern |
| none | `Object` | `toString()` |

### Numbers

```json
"balance": "Balance: {amount}",
"@balance": {
  "placeholders": {
    "amount": {
      "type": "double",
      "format": "currency",
      "optionalParameters": { "symbol": "$", "decimalDigits": 2 }
    }
  }
}
```

`format` is any `NumberFormat` constructor: `compact`, `compactLong`, `currency`, `simpleCurrency`, `decimalPattern`, `percentPattern`, `scientificPattern` and the others. `optionalParameters` are passed to it as named arguments.

### Dates

```json
"lastSeen": "Last seen {date}",
"@lastSeen": {
  "placeholders": {
    "date": { "type": "DateTime", "format": "yMMMd" }
  }
}
```

`format` is a `DateFormat` constructor name such as `yMMMd`, `yMd`, `jm` or `MMMMEEEEd`. For your own pattern, add `"isCustomDateFormat": "true"` and write the pattern: `"format": "dd/MM/yyyy"`.

## Plurals

```json
"cartItems": "{count, plural, =0{Your cart is empty} one{1 item} other{{count} items}}",
"@cartItems": {
  "placeholders": { "count": { "type": "int" } }
}
```

- Categories: `zero`, `one`, `two`, `few`, `many`, `other`, and exact matches like `=0` or `=12`. Which categories a language uses depends on the language: Arabic uses all six, Japanese only `other`.
- `other` is required.
- `#` inside a branch is the number: `other{# items}`.
- `offset:1` subtracts from the number before choosing the branch, for texts like "You and 3 others".

## Select

For gender and other fixed choices:

```json
"greeting": "{gender, select, male{He is online} female{She is online} other{They are online}}"
```

The parameter is a `String`. `other` is required.

## Ordinals

```json
"rank": "You finished {place, selectordinal, one{#st} two{#nd} few{#rd} other{#th}}"
```

Ordinal rules come from CLDR and are compiled into the generated code, so English gives 1st, 2nd, 3rd, 11th, 21st and 23rd correctly.

## Nesting

Plurals, selects and ordinals can be nested to any depth:

```json
"invites": "{gender, select, female{{count, plural, one{She invited one friend} other{She invited {count} friends}}} other{{count, plural, one{They invited one friend} other{They invited {count} friends}}}}"
```

## Escaping

Wrap literal braces in single quotes: `'{'not a placeholder'}'`. Two single quotes (`''`) are one apostrophe.

## Mistakes the tools catch

`check` (and the GUI's **Check** action) reports:

- ICU syntax errors, with the position;
- a plural or select without `other`;
- placeholders in a translation that do not match the default locale's;
- placeholder names that are Dart keywords;
- a `#` outside a plural, which is printed as a literal `#`;
- missing locale files, missing keys, and empty translations.

See [Keeping translations healthy](/guides/quality/).
