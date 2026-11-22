---
title: Coming from the VS Code extension
description: How the Modular Flutter L10n extension's commands map to this package, and what differs.
---

This package is the editor-independent version of the [Modular Flutter L10n](https://marketplace.visualstudio.com/items?itemName=UtaniumOrg.modular-flutter-l10n) VS Code extension. It reads the same `modular_l10n:` settings and writes byte-for-byte the same generated code, so one team can use both without the generated files changing back and forth.

## Command by command

| Extension command | Command | GUI action |
|---|---|---|
| Initialize | `init` | Initialize |
| Generate Translations | `generate` (or no command) | Generate (`g`) |
| Create New Module | `create-module` | Create module (`m`) |
| Add l10n Folder | `create-module --dir <folder>` | Create module (`m`) |
| Add Translation Key | `add-key` | Add key (`a`) |
| Rename Translation Key | `rename-key` | Rename key |
| Add Locale | `add-locale` | Add locale (`l`) |
| Remove Locale | `remove-locale` | Remove locale |
| Generate Pseudo-Locale | `pseudo-locale` | Pseudo-locale |
| Check Missing Translations | `check` | Check (`c`) |
| Find Unused Keys | `unused` | Unused keys |
| Sort ARB Keys | `sort` | Sort keys |
| Scan Hardcoded Strings | `hardcoded` | Hardcoded strings (`h`) |
| Extract String to ARB | `extract` | Hardcoded strings (`h`) → Enter |
| Export Translations (CSV/XLIFF) | `export` | Export |
| Import Translations (CSV/XLIFF) | `import` | Import |
| Migrate from Flutter Intl | `migrate` | Migrate from Flutter Intl |
| Check Compatibility with Flutter Intl | `doctor` | Doctor (`d`) |
| Auto-generate on save | `watch` | `w` (watch mode) |

Only here: the **Translate** screen, the **Settings** screen, `sort --check` and `check` exit codes for CI, and `doctor --fix`.

## Editor features

These need an editor, so they stay in the extension:

- hover previews of a key's translations;
- go to definition from `ML.of(context).auth.emailLabel` to the ARB entry;
- squiggles under ICU mistakes while you type.

`check` reports the same ICU problems, with file names, and `watch` or the GUI's watch mode regenerates on save.

## Behaviour differences

- Commands never overwrite an existing ARB file without `--overwrite`.
- `import` only fills keys that exist in the default locale and ignores empty cells, so a partial spreadsheet cannot erase translations. Each file is written once.
- `rename-key` keeps the key's position in the file.
- `extract` drops a `const` directly before the widget, since the lookup is not constant.
- Renaming and unused-key detection use the effective default locale (the configured one, or the first locale with files if it has none), like generation does.
- `pubspec.yaml` is edited in place, keeping comments and formatting.
- Settings that collide with Flutter Intl are refused with a message, with `--force` to override, instead of a prompt.
- `--fatal-warnings` lets CI fail on warnings.
