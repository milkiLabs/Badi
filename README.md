# Badi

A fast, keyboard-driven application launcher built with Zig and Qt.

Press a shortcut, type to search, and launch apps instantly.

Badi in arabic means Starter or initiator. Starts programs and commands.

## Modes

| Mode | Trigger | What it does |
|------|---------|--------------|
| **Apps** | Default (no pipe) | Scans `.desktop` files, lets you search and launch apps |
| **Piped** | `stdin` is a pipe | Streams lines from stdin, filter and select one (dmenu-style) |
| **Prefix** | Type a trigger (e.g. `g `) | Runs a shell command template with your query |
| **URL** | Type a URL (e.g. `example.com`) | Opens it in the default browser via `xdg-open` |
| **Prompt** | `--prompt [LABEL]` | Shows a labeled input; the typed text is written to stdout on Enter |
| **Emoji** | `--emoji` or type `": "` | Picks an emoji from a pre-packed Unicode list and copies/types/prints it |

## Prerequisites

This project requires **Zig 0.16.0+** and **Qt 6 development libraries** (Core, Gui, Widgets).

Install Zig from [ziglang.org/download](https://ziglang.org/download/).

### Arch

```bash
sudo pacman -S gcc qt6-base
```

### Debian/Ubuntu

```bash
sudo apt install gcc g++ qt6-base-dev
```

### Fedora

```bash
sudo dnf install gcc gcc-c++ qt6-qtbase-devel
```

### openSUSE

```bash
sudo zypper install gcc gcc-c++ qt6-base-devel
```

> For the full list of additional Qt modules, and third-party library support, see the [libqt6zig Building guide](https://github.com/rcalixte/libqt6zig#building).

## Quick Start

```bash
git clone <repo-url> && cd badi
zig build run
```

The first build takes a few minutes (compiling libqt6zig static wrappers). Subsequent builds are fast.

## Building

```bash
zig build                            # debug build
zig build -Doptimize=ReleaseFast     # optimized (fastest, best for production)
zig build -Doptimize=ReleaseSmall    # optimized (smallest binary)
zig build test                       # run tests
```

The output binary is at `zig-out/bin/Badi`.

## Project Structure

```
build.zig            — Build configuration
build.zig.zon        — Pinned dependencies (libqt6zig)
src/
  main.zig           — Thin entry shim → app.App.create + run
  core_tests.zig     — Test runner for non-Qt modules
  app/               — App lifecycle (create / run / destroy), CLI parsing, startup sequencing
    cli.zig          — --prompt flag parsing
    startup.zig      — buildState, resolveMode, prepareInitialFrame
    exit_code.zig    — post-event-loop exit code resolution
  state/             — AppState, AppMode, Widgets bundle, C-ABI global pointer
  config/            — JSON config loaders (theme, actions) + QSS generator
  core/              — Pure logic, no Qt
    filter.zig       — Generic fuzzy+substring filter
    search.zig       — Scoring engine (substring, multi-token, acronym)
    exec.zig         — Exec string parsing, shell quoting
    desktop/         — XDG .desktop file discovery
    emoji/           — Pre-packed binary emoji slab + loader
  modes/             — Per-mode launch dispatch
    apps.zig         — Launch a .desktop entry
    piped.zig        — Print selected stdin line
    prefix.zig       — Run a shell template
    url.zig          — Open a URL with xdg-open
    prompt.zig       — Write prompt answer to stdout
    emoji.zig        — Copy/print/type the selected glyph
  ui/                — Qt widget code
    factory.zig      — Build widgets, wire signals, apply theme
    view.zig         — Filter, selection, scroll
    model.zig        — QAbstractListModel callbacks
    status.zig       — "No results / waiting" label
    piped_view.zig   — Async piped-list maintenance
    callbacks/       — Signal handlers, split by signal type
      text.zig       — onTextChanged (prefix/URL detection, re-filter)
      key.zig        — onKeyPress (Enter, Esc, arrows, Ctrl-W)
      click.zig      — onItemDoubleClicked
      piped.zig      — onStdinActivated (stdin reader)
      helpers.zig    — exitToApps, enterPrefixMode, enterUrlMode, enterEmojiMode
  utils/url.zig      — isUrl() — URL detection for auto-mode-switch
docs/
  codebase-structure.md — Module layering & rules (read this first)
  architecture.md    — Mode detection and startup flow
  app-lifecycle.md   — App.create → run → destroy sequence
  modes.md           — Per-mode behavior reference
  performance.md     — Performance optimizations
  piped-mode.md      — Piped mode internals
  prompt-mode.md     — Prompt mode internals
  emoji-mode.md      — Emoji picker internals
  stdin-detection.md — TTY vs pipe vs /dev/null detection
  user-docs/         — End-user configuration
    actions.md       — Prefix action configuration
    theme.md         — Theme configuration
    search-algo.md   — Search algorithm details
    shortcuts.md     — Keyboard shortcuts reference
```

## Usage

```bash
badi                         # Launch app selector
echo -e "foo\nbar\nbaz" | badi   # Piped mode (dmenu-style)
name=$(badi --prompt "Name: ")    # Prompt mode — for shell scripts
badi --emoji                # Emoji picker (copies selection to clipboard)
```

### Prompt Mode

For shell scripts that need a free-form text answer. Whatever the user types
is written to stdout on Enter; Escape cancels with exit code 1.

```bash
name=$(badi --prompt "Name: ")
repo=$(badi --prompt "Repo: " --default "badi")
token=$(badi --prompt "API token: " --password)
```

| Flag             | Effect                                                       |
| ---------------- | ------------------------------------------------------------ |
| `--prompt LABEL` | Enter prompt mode. `LABEL` is shown as an inline chip.       |
| `--default TEXT` | Pre-fill the input and select all.                           |
| `--password`     | Mask the input characters.                                   |
| `--allow-empty`  | Permit Enter on an empty input (rejected by default).        |

See [docs/prompt-mode.md](docs/prompt-mode.md) for details.

### Emoji Mode

A built-in emoji picker. Search the Unicode emoji set by name or keyword,
and the selection is routed to one of three actions (default: clipboard).

```bash
badi --emoji              # picker → copy to clipboard
badi --emoji --print      # picker → write glyph to stdout
badi --emoji --type       # picker → type into focused window
```

You can also enter emoji mode mid-session by typing `": "` while in apps mode.

| Flag       | Effect                                                         |
| ---------- | -------------------------------------------------------------- |
| `--emoji`  | Enter emoji mode (initial). Mutually exclusive with `--prompt`. |
| `--copy`   | Copy the selected glyph to the clipboard (default).            |
| `--print`  | Write the glyph to stdout, exit 0.                             |
| `--type`   | Synthesize keystrokes (wtype on Wayland, xdotool on X11).      |

See [docs/emoji-mode.md](docs/emoji-mode.md) for details.

### Prefix Actions

Type a trigger in the search box to switch modes:

- `g ` — Google search
- `> ` — Run shell command

Configure in `~/.config/badi/config.json`. See [docs/user-docs/actions.md](docs/user-docs/actions.md).

### Theming

Customize colors, fonts, and dimensions in `~/.config/badi/theme.json`. See [docs/user-docs/theme.md](docs/user-docs/theme.md).

## Learn More

| Topic                           | Link                                                                 |
| ------------------------------- | -------------------------------------------------------------------- |
| Codebase structure              | [docs/codebase-structure.md](docs/codebase-structure.md)             |
| Architecture and startup flow   | [docs/architecture.md](docs/architecture.md)                         |
| App lifecycle (create/run/destroy) | [docs/app-lifecycle.md](docs/app-lifecycle.md)                     |
| Per-mode behavior reference     | [docs/modes.md](docs/modes.md)                                       |
| Prompt mode (script input)      | [docs/prompt-mode.md](docs/prompt-mode.md)                           |
| Piped mode (dmenu-style)        | [docs/piped-mode.md](docs/piped-mode.md)                             |
| Emoji mode internals            | [docs/emoji-mode.md](docs/emoji-mode.md)                             |
| Stdin detection logic           | [docs/stdin-detection.md](docs/stdin-detection.md)                   |
| Performance notes               | [docs/performance.md](docs/performance.md)                           |
| How the API differs from Qt C++ | [libqt6zig FAQ Q3](https://github.com/rcalixte/libqt6zig#faq)        |
| More example applications       | [libqt6zig-examples](https://github.com/rcalixte/libqt6zig-examples) |
| Signals, slots, subclassing     | [libqt6zig Usage](https://github.com/rcalixte/libqt6zig#usage)       |
| Build options                   | `zig build --help`                                                   |
| Full library documentation      | [rcalixte.github.io/libqt6zig](https://rcalixte.github.io/libqt6zig) |

## Acknowledgments

- [libqt6zig](https://github.com/rcalixte/libqt6zig) — Qt 6 Zig bindings
- [muan/unicode-emoji-json](https://github.com/muan/unicode-emoji-json) — Unicode emoji data
- [muan/emojilib](https://github.com/muan/emojilib) — emoji keywords

## License
