# Architecture: Mode Detection and Startup

## Overview

Badi operates in one of three modes:

```
┌──────────────────────────────────────────────────┐
│                   Badi Startup                    │
├──────────────────────────────────────────────────┤
│                                                   │
│  stdin.stat().kind == .named_pipe?                 │
│       │                                           │
│       ├── YES ──→ Piped Mode                     │
│       │            show window immediately        │
│       │            QSocketNotifier on stdin       │
│       │            stream lines as they arrive    │
│       │                                           │
│       └── NO ───→ Apps Mode                     │
│                    load .desktop files sync       │
│                    populate list                  │
│                    show window                    │
│                                                   │
└──────────────────────────────────────────────────┘
```

## Piped Mode

Triggered when stdin is a real pipe (FIFO). Used for `dmenu`-style workflows:

```bash
echo -e "foo\nbar\nbaz" | badi
find / -type f | badi
```

### Startup sequence

1. Show window with "Waiting for input…"
2. Create `QSocketNotifier` on `STDIN_FILENO`
3. Enter `QApplication.Exec()` (Qt event loop)
4. As data arrives, `onStdinActivated` fires:
   - Reads up to 64 KB via `std.posix.read`
   - Buffers partial lines in `stdin_pending`
   - Complete lines are dispatched to `appendPipedItem`
5. User types to filter, presses Enter to select
6. Selected line is written to stdout; exit code 0
7. Escape → exit code 1

### Key files

- `src/main.zig` — notifier creation
  - `const notifier = qt6.QSocketNotifier.New4(...);`
- `src/ui/callbacks.zig` — stdin reading pipeline
  - `pub fn onStdinActivated(...)`
- `src/ui/window.zig` — incremental list population
  - `appendPipedItem`

## Apps Mode

Triggered when stdin is NOT a pipe (terminal, `/dev/null`, file redirect).
Used for the primary desktop app launcher:

```bash
badi                    # from terminal
$mod+p                  # from Sway keybinding (stdin = /dev/null)
```

### Startup sequence

1. Load `.desktop` files synchronously via `desktop.loadDesktopApps()`
2. Build `piped_items` is empty; `app_list` is populated
3. Build filtered source indexes and reset the list model
4. Show window (fully interactive from the first frame)

### Why synchronous loading?

Loading `.desktop` files is a blocking filesystem scan (~200+ files). Running
it synchronously before `Show()` means the window is fully responsive the
moment it appears. The scan typically completes in under 100 ms on modern
hardware with warm disk caches.

### Key files

- `src/main.zig` — synchronous desktop loading
  - `app_list = try desktop.loadDesktopApps(...)`
- `src/main.zig` — list population and show
  - `window.filterList("")`
- `src/core/desktop.zig` — `.desktop` file parsing

## Prefix Mode

Entered when the user types a trigger string (e.g. `g ` for Google search.
The active prefix is stored as a `config.Action` in `AppMode.prefix`.

### Key files

- `src/ui/callbacks.zig` — trigger detection in `onTextChanged`
- `src/ui/window.zig` — prefix row display
  - `onModelData`
- `src/ui/callbacks.zig` — `exitPrefixMode()` helper

## Exit Codes

| Condition                          | Exit code |
| ---------------------------------- | --------- |
| Item selected (Enter/double-click) | 0         |
| Escape pressed in piped mode       | 1         |
| Escape pressed in apps mode        | 0         |
| Window closed via window manager   | 0         |
