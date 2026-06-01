# Keyboard Shortcuts

## Navigation

| Shortcut | Action                                   |
| -------- | ---------------------------------------- |
| Enter    | Launch selected item (or submit prompt)  |
| Up       | Select previous item                     |
| Down     | Select next item (wraps around)          |

## Escape

Behavior depends on the current mode:

| Mode              | Escape behavior                                  |
| ----------------- | ------------------------------------------------ |
| `apps`            | Close the window (exit code 0)                   |
| `prefix`          | Exit back to apps mode (input cleared)           |
| `url`             | Exit back to apps mode (input cleared)           |
| `piped`           | Close the window (exit code 1)                   |
| `prompt`          | Cancel — close the window (exit code 1)          |

## Editing

| Shortcut     | Action                                                          |
| ------------ | --------------------------------------------------------------- |
| Ctrl+C       | Clear the input                                                 |
| Ctrl+W       | Delete previous word; in `prefix`/`url` on empty input, exit to apps |
| Backspace    | Delete character before cursor; in `prefix`/`url` on empty input, exit to apps |

In `prefix` and `url` modes, **Backspace** and **Ctrl+W** on an empty
input both fall back to exiting the mode and returning to apps mode.
This makes the prefix/URL layer feel like an inline form rather than a
modal dialog.

## Built-in (Qt)

These work out of the box via Qt's default handling on `QLineEdit`:

| Shortcut        | Action                             |
| --------------- | ---------------------------------- |
| Ctrl+A          | Select all text                    |
| Ctrl+Z          | Undo                               |
| Ctrl+Y          | Redo                               |
| Ctrl+X          | Cut selected text                  |
| Ctrl+V          | Paste                              |
| Home / End      | Move cursor to start / end of line |
| Ctrl+Left/Right | Move cursor by word                |
| Shift+Arrow     | Select text                        |
| Ctrl+Backspace  | Delete previous word (Qt default)  |
