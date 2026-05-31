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
  main.zig           — Entry point, bootstrap, Qt event loop
  config.zig         — Theme and action JSON config loading
  context.zig        — Global AppState, mode definitions
  core_tests.zig     — Test runner for core modules
  core/
    desktop.zig      — .desktop file discovery and parsing
    exec.zig         — Exec string parsing (quotes, field codes)
    launcher.zig     — Launch/execute the selected item
  ui/
    callbacks.zig    — Qt signal callbacks (text change, key press, stdin)
    window.zig       — QListView model callbacks, filter, select
docs/
  architecture.md    — Mode detection and startup design
  actions.md         — Prefix action configuration
  theme.md           — Theme configuration
  performance.md     — Performance optimizations
  piped-mode.md      — Piped mode internals
  stdin-detection.md — TTY vs pipe vs /dev/null detection
  build-changes.md   — Qt library additions
  codebase-structure.md — Core vs UI separation guide
```

## Usage

```bash
badi                         # Launch app selector
echo -e "foo\nbar\nbaz" | badi   # Piped mode (dmenu-style)
```

### Prefix Actions

Type a trigger in the search box to switch modes:

- `g ` — Google search
- `> ` — Run shell command

Configure in `~/.config/badi/config.json`. See [docs/actions.md](docs/actions.md).

### Theming

Customize colors, fonts, and dimensions in `~/.config/badi/theme.json`. See [docs/theme.md](docs/theme.md).

## Learn More

| Topic                           | Link                                                                 |
| ------------------------------- | -------------------------------------------------------------------- |
| Architecture and modes          | [docs/architecture.md](docs/architecture.md)                         |
| Codebase structure              | [docs/codebase-structure.md](docs/codebase-structure.md)             |
| How the API differs from Qt C++ | [libqt6zig FAQ Q3](https://github.com/rcalixte/libqt6zig#faq)        |
| More example applications       | [libqt6zig-examples](https://github.com/rcalixte/libqt6zig-examples) |
| Signals, slots, subclassing     | [libqt6zig Usage](https://github.com/rcalixte/libqt6zig#usage)       |
| Build options                   | `zig build --help`                                                   |
| Full library documentation      | [rcalixte.github.io/libqt6zig](https://rcalixte.github.io/libqt6zig) |

## Acknowledgments

Thanks to [libqt6zig](https://github.com/rcalixte/libqt6zig) for the Qt 6 Zig bindings that make this project possible.

## License
