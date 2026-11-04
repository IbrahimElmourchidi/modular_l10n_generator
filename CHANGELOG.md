## 1.0.0

- First release: a command-line port of the code generator in the Modular Flutter L10n VS Code extension (4.2.0).
- `generate` and `watch` commands, configured from the `modular_l10n:` section of `pubspec.yaml`, with command-line overrides.
- Output is byte-for-byte identical to the extension's. A test suite checks it against the extension's own output for its ICU fixture corpus.
- Differences from the extension:
  - Settings that collide with Flutter Intl are refused, with a `--force` escape hatch, instead of prompting.
  - Two output directories nested inside each other are allowed. Only the same directory counts as a collision.
  - `--fatal-warnings` lets CI fail on warnings.
  - Malformed `pubspec.yaml` is reported as an error instead of silently ignored.
