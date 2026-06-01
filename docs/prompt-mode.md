# Prompt Mode

A fourth mode, designed for shell scripts. The user is shown a single-line
input (optionally labeled, optionally pre-filled, optionally masked). Whatever
they type is written to stdout on **Enter**; **Escape** cancels with exit
code 1. The list view is hidden, the window shrinks to a single row.

## Usage

```bash
badi --prompt [LABEL] [OPTIONS]
```

| Flag             | Effect                                                       |
| ---------------- | ------------------------------------------------------------ |
| `--prompt LABEL` | Enter prompt mode. `LABEL` is shown as an inline chip. Omit for no label. |
| `--default TEXT` | Pre-fill the input and select all (Enter accepts, typing overwrites). |
| `--password`     | Mask the input (`QLineEdit::Password` echo mode).            |
| `--allow-empty`  | Permit Enter on an empty input. By default empty submits are rejected. |

## Examples

```bash
# Bare prompt
name=$(badi --prompt "Name: ")
echo "hello, $name"

# With a default the user can accept
repo=$(badi --prompt "Repo: " --default "badi")

# Secure input for a token
token=$(badi --prompt "API token: " --password)

# Allow empty (e.g. an optional description)
desc=$(badi --prompt "Description: " --allow-empty)
```

## Behavior

- **Window**: same width as the launcher, height shrunk to 80px. The
  `QListView` and "no results" label are hidden — the layout treats hidden
  children as zero-size, so the window collapses to the input row + padding.
- **Window title**: `Badi` by default, or `Badi — <label>` when a label is set.
  This makes the prompt identifiable in the WM taskbar.
- **Label UX**: shown as an inline chip (the existing `QLabel` badge) before
  the input. Reuses the launcher's theming.
- **Placeholder**: shown only when no label is provided ("Type and press Enter…").
  When a label is set, the label itself is the prompt — no extra placeholder.
- **Stdin is ignored** in prompt mode. `--prompt` overrides piped-mode
  detection, so scripts that pipe data to Badi can still invoke a prompt.
  No `QSocketNotifier` is installed.
- **Output**: typed text + trailing newline (`\n`), written via the same
  `std.Io.File.stdout()` path that piped mode uses.
- **Exit codes**:

  | Condition                | Exit code |
  | ------------------------ | --------- |
  | Enter (with non-empty)   | 0         |
  | Enter (empty, allowed)   | 0         |
  | Enter (empty, rejected)  | n/a — window stays open, no submit |
  | Escape / window closed   | 1         |

## Why a CLI flag (not stdin detection)?

`--prompt` is explicit and overrides the auto-detect logic. This means:

- A script can pipe data to Badi for piped mode but invoke `--prompt` for a
  single user query without ambiguity.
- The label travels with the invocation (`badi --prompt "Name: "`) — no
  separate env var or config to set.
- A Sway keybinding (where stdin is `/dev/null`) can still launch a prompt.

## Why reject empty submits by default?

Most `read`-style prompts in shell scripts want a value. An accidental Enter
on an empty field would otherwise silently flow an empty string into the
script, which is rarely what the user wants. `--allow-empty` opts in to the
more permissive behavior.
