---
title: Android Studio and IntelliJ
description: Regenerate on save, run the GUI in the IDE terminal, and extract strings from the editor.
---

There is no plugin to install. The GUI runs in the IDE's terminal, and the commands plug into the IDE's own tools.

## Open the GUI

Open the **Terminal** tool window (Alt+F12) and run:

```sh
dart run modular_l10n_generator gui
```

Drag the terminal tab to the editor area for more room. Press `w` to turn on watch mode, so ARB files you edit in the IDE regenerate the code on save.

## Regenerate on save (File Watcher)

1. Install the **File Watchers** plugin (*Settings → Plugins*).
2. Open *Settings → Tools → File Watchers*, click **+** and choose **Custom**.
3. Fill in:

   | Field | Value |
   |---|---|
   | File type | `JSON` (or *Any* with the scope below) |
   | Scope | a custom scope with the pattern `file:*/l10n/*.arb` |
   | Program | `dart` (or the full path to the Flutter SDK's `bin/dart`) |
   | Arguments | `run modular_l10n_generator --quiet` |
   | Working directory | `$ProjectFileDir$` |

4. Under **Advanced Options**, untick *Auto-save edited files to trigger the watcher*, and tick *Trigger the watcher on external changes*.

ARB files may not be associated with JSON. If so, add `*.arb` under *Settings → Editor → File Types → JSON*.

## Run watch mode in the background

*Run → Edit Configurations → + → Shell Script*. Choose *Script text*, enter `dart run modular_l10n_generator watch`, and set the working directory to the project root. Start it once per session and leave it running.

## Generate from a menu or shortcut

*Settings → Tools → External Tools → +*:

| Field | Value |
|---|---|
| Name | Generate translations |
| Program | `dart` |
| Arguments | `run modular_l10n_generator` |
| Working directory | `$ProjectFileDir$` |

It appears under *Tools → External Tools*. Give it a shortcut in *Settings → Keymap → External Tools*.

## Extract the string under the cursor

Add another External Tool:

| Field | Value |
|---|---|
| Name | Extract string to ARB |
| Program | `dart` |
| Arguments | `run modular_l10n_generator extract --file $FilePath$ --line $LineNumber$ --column $ColumnNumber$ --module $Prompt$` |
| Working directory | `$ProjectFileDir$` |

Put the cursor inside a string and run it. `$Prompt$` opens a dialog that asks for the module; the key name is suggested from the text. Replace `$Prompt$` with a module name to always use the same one.

External Tools do not run in an interactive terminal, so every value must be on the command line; a missing one stops the command with exit code 64 instead of asking.

## Check before you commit

One more External Tool, with the arguments `run modular_l10n_generator check`, lists missing translations and ICU mistakes in the Run window. Each line names the ARB file.
