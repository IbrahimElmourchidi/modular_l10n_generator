---
title: Configuration
description: Every setting of the modular_l10n section in pubspec.yaml.
---

All settings are optional and live in the `modular_l10n:` section of `pubspec.yaml`. These are the defaults:

```yaml title="pubspec.yaml"
modular_l10n:
  enabled: true
  class_name: ML
  default_locale: en
  output_dir: lib/generated/modular_l10n
  arb_dir_pattern: "**/l10n/*.arb"
  generate_combined_arb: true
  use_deferred_loading: false
  module_access: part
  log_level: warning
```

The GUI's **Settings** screen edits them for you, keeping the file's comments and formatting. The VS Code extension reads the same section.

## Settings

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | `false` turns generation off. Commands still edit ARB files. |
| `class_name` | `ML` | The generated entry-point class: `ML.of(context)`. Must be a valid Dart class name, and must not be `S` when Flutter Intl is also used. |
| `default_locale` | `en` | The template locale. Its keys define what exists, its metadata defines placeholders, and other locales fall back to it. If no ARB file has this locale, the first locale found is used, with a warning. |
| `output_dir` | `lib/generated/modular_l10n` | Where the code is generated, relative to the project root. Must differ from Flutter Intl's output folder. |
| `arb_dir_pattern` | `**/l10n/*.arb` | Glob, relative to the project root, that finds ARB files. Files without `@@locale` and `@@context` are ignored. |
| `generate_combined_arb` | `true` | Also write one merged ARB file per locale to `<output_dir>/arb/`, for tools that expect a single file. |
| `use_deferred_loading` | `false` | Load each locale's messages lazily. Makes the initial download smaller on the web. |
| `module_access` | `part` | `part`: module files are parts of the entry point, so `ML` is the only way in. `library`: each module file can be imported directly. |
| `log_level` | `warning` | `silent`, `error`, `warning` or `verbose`. |

## Overriding from the command line

`generate` and `watch` take flags that override the file, key by key, for that run:

| Flag | Overrides |
|---|---|
| `--class-name` | `class_name` |
| `--default-locale` | `default_locale` |
| `--output-dir` | `output_dir` |
| `--arb-pattern` | `arb_dir_pattern` |
| `--module-access` | `module_access` |
| `--[no-]combined-arb` | `generate_combined_arb` |
| `--[no-]deferred-loading` | `use_deferred_loading` |
| `--log-level`, `-v`, `-q` | `log_level` |

## The project root

Every command finds the project by walking up from the current folder to the nearest `pubspec.yaml`. Pass `--root <dir>` to point at another project.
