---
title: CI
description: Fail the build on missing translations, ICU mistakes, unsorted files and stale generated code.
---

Every command works without a terminal. Commands never wait for input in CI: a missing value is a usage error (exit code `64`), and commands that delete files need `--yes`.

## The checks

```sh
dart run modular_l10n_generator --fatal-warnings  # generate; fail on warnings
git diff --exit-code lib/generated/modular_l10n   # someone forgot to regenerate
dart run modular_l10n_generator check             # missing translations, ICU mistakes
dart run modular_l10n_generator sort --check      # ARB keys kept sorted
```

Skip the `git diff` line if the generated code is not committed.

Stricter options, to add when the project is clean:

```sh
dart run modular_l10n_generator check --fatal-warnings  # empty translations fail too
dart run modular_l10n_generator check --unused --hardcoded --fatal-warnings
```

## GitHub Actions

```yaml title=".github/workflows/l10n.yml"
name: Translations
on: [push, pull_request]

jobs:
  l10n:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: dart run modular_l10n_generator --fatal-warnings
      - run: git diff --exit-code lib/generated/modular_l10n
      - run: dart run modular_l10n_generator check
      - run: dart run modular_l10n_generator sort --check
```

## GitLab CI

```yaml title=".gitlab-ci.yml"
l10n:
  image: ghcr.io/cirruslabs/flutter:stable
  script:
    - flutter pub get
    - dart run modular_l10n_generator --fatal-warnings
    - git diff --exit-code lib/generated/modular_l10n
    - dart run modular_l10n_generator check
    - dart run modular_l10n_generator sort --check
```

## A pre-commit hook

```sh title=".git/hooks/pre-commit"
#!/bin/sh
dart run modular_l10n_generator --quiet && \
dart run modular_l10n_generator sort --check --quiet && \
git add lib/generated/modular_l10n
```

Make it executable with `chmod +x .git/hooks/pre-commit`.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Generation failed, `check` found errors, `sort --check` found unsorted files, or warnings under `--fatal-warnings` |
| `64` | Usage error: unknown option, invalid value, or a value that would have been asked for in a terminal |
