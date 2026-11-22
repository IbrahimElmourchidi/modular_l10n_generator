## 1.1.0

- **Terminal GUI**: `dart run modular_l10n_generator gui` opens a full-screen app with every action in a sidebar, guided steps, a folder browser for picking where a module goes, a live log, and a watch-mode toggle. Keyboard and mouse.
- **New commands**, ported from the VS Code extension. Each one also works from scripts and CI with flags, and asks for missing values when run in a terminal:
  - Project: `init`, `doctor` (setup and Flutter Intl conflict check, `--fix`).
  - Modules and keys: `create-module`, `add-key`, `rename-key` (updates Dart code too, `--dry-run`).
  - Locales: `add-locale`, `remove-locale`, `pseudo-locale`.
  - Quality: `check` (missing and empty translations, ICU mistakes, direct module imports; exit code 1 on errors), `sort` (`--check` for CI), `unused` (`--remove`), `hardcoded`, `extract`.
  - Exchange: `export` / `import` (CSV and XLIFF 1.2), `migrate` (from Flutter Intl).
- GUI-only: a **Translate** screen that walks through every missing or empty translation, and a **Settings** screen for the `modular_l10n:` section of `pubspec.yaml`.
- Short executable name: `ml10n` (after `dart pub global activate modular_l10n_generator`).
- Differences from the extension's commands:
  - Commands never overwrite an existing ARB file without `--overwrite`.
  - `import` only fills keys that exist in the default locale and ignores empty cells, so a partial spreadsheet cannot erase translations. It writes each file once.
  - `rename-key` keeps the key's position in the file.
  - `extract` drops a `const` directly before the widget, since the lookup is not constant.
  - Rename and unused-key detection use the effective default locale, like generation does.
  - `pubspec.yaml` is edited in place, keeping comments and formatting.
- The ops are exported from the library for build scripts.
- Documentation website with guides, a command reference and recorded GUI demos: https://modular-l10n.example.com

## 1.0.0

- First release: a command-line port of the code generator in the Modular Flutter L10n VS Code extension (4.2.0).
- `generate` and `watch` commands, configured from the `modular_l10n:` section of `pubspec.yaml`, with command-line overrides.
- Output is byte-for-byte identical to the extension's. A test suite checks it against the extension's own output for its ICU fixture corpus.
- Differences from the extension:
  - Settings that collide with Flutter Intl are refused, with a `--force` escape hatch, instead of prompting.
  - Two output directories nested inside each other are allowed. Only the same directory counts as a collision.
  - `--fatal-warnings` lets CI fail on warnings.
  - Malformed `pubspec.yaml` is reported as an error instead of silently ignored.
