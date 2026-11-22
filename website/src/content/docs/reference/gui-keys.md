---
title: GUI keys
description: Every key the terminal GUI understands.
---

The last line of the GUI always shows the keys that work at that moment, and `?` opens the help screen.

## Main screen

| Key | Does |
|---|---|
| ↑ ↓, `j` `k` | Move in the action list |
| Enter, → | Open the selected action |
| `g` | Generate |
| `d` | Doctor |
| `m` | Create module |
| `a` | Add key |
| `t` | Translate |
| `l` | Add locale |
| `c` | Check |
| `h` | Hardcoded strings |
| `w` | Watch mode on or off |
| `v` | Larger or smaller log panel |
| `r` | Reload the project from disk |
| `?` | Help |
| `q`, Esc, Ctrl+C | Quit |

Actions without a letter are opened with the arrow keys and Enter, or a mouse click.

## Inside an action

| Where | Key | Does |
|---|---|---|
| Anywhere | Esc | Back one step; cancels the action |
| Anywhere | Ctrl+C | Quit |
| List | ↑ ↓, Page Up/Down, Home/End | Move |
| List | Enter | Choose |
| List with "Type to filter…" | letters, Backspace | Filter the list |
| Multi-select list | Space | Select or unselect |
| Multi-select list | `a` | Select or unselect all |
| Multi-select list | Enter | Continue with the selection |
| Text field | Enter | Accept (the field shows a message if the value is invalid) |
| Text field with suggestions | Tab | Next suggestion |
| Confirmation | `y` | Yes |
| Confirmation | Enter | Yes, except for destructive steps |
| Confirmation | `n`, Esc | No |
| Result | Enter, Esc | Close |
| Result, confirmation | ↑ ↓ | Scroll |

## Folder browser

| Key | Does |
|---|---|
| ↑ ↓, `j` `k` | Move |
| Enter, → | Open the folder, or run the selected row |
| ←, Backspace | Up one folder (never above the project root) |
| `n` | New folder here |
| Esc | Cancel |

The first row (**▶ Create here**, **▶ Save here** or **▶ Use this folder**) selects the folder you are in. Hidden folders, `build/` and the generated output folder are not shown.
