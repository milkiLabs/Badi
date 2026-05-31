# Codebase Structure: Core vs UI Separation

Badi separates business logic from Qt widget manipulation. This document
explains the layering, what lives where, and the rules that keep the boundary
clean.

## Layer Diagram

```
┌─────────────────────────────────────────────────────┐
│                    src/main.zig                     │
│           Bootstrap / wiring / event loop           │
├────────────────────┬────────────────────────────────┤
│      core/         │            ui/                 │
│  Pure logic,       │  Qt widget manipulation,       │
│  no Qt deps        │  signal callbacks              │
│  (except launcher) │                                │
├────────────────────┼────────────────────────────────┤
│  desktop.zig       │  callbacks.zig                 │
│  exec.zig          │  window.zig                    │
│  launcher.zig      │                                │
├────────────────────┴────────────────────────────────┤
│                  context.zig                        │
│      Shared AppState — the glue layer               │
├─────────────────────────────────────────────────────┤
│                  config.zig                         │
│     Theme + action JSON config loading              │
└─────────────────────────────────────────────────────┘
```

## Module Responsibilities

### `core/` — Business Logic

| File           | Deps                    | Purpose                                           |
| -------------- | ----------------------- | ------------------------------------------------- |
| `desktop.zig`  | std only                | XDG `.desktop` file discovery, parsing, filtering |
| `exec.zig`     | std only                | FreeDesktop exec string parsing, shell quoting    |
| `launcher.zig` | std, qt6, context, exec | Dispatches launch commands via `QProcess`         |

`desktop.zig` and `exec.zig` are **pure Zig** — no Qt imports. They can be
tested, reused, or extracted without any Qt dependency.

`launcher.zig` uses Qt (`QProcess`) to detach launched commands. It asks
`ui/window.zig` for the current app-side selection instead of reading data back
out of Qt rows.

### `ui/` — Qt Widget Manipulation

| File            | Deps                                | Purpose                                              |
| --------------- | ----------------------------------- | ---------------------------------------------------- |
| `callbacks.zig` | std, qt6, context, window, launcher | Signal handlers for text changes, key presses, stdin |
| `window.zig`    | std, qt6, context                   | QListView model callbacks, filter, select            |

These files are the only ones that directly manipulate Qt widgets. They never
parse `.desktop` files or exec strings — they delegate to `core/`.

### `context.zig` — The Glue Layer

Defines `AppState` (the single source of truth) and `AppMode` (tagged union
of `apps`, `piped`, `prefix`). Provides a global pointer pattern for Qt
callbacks that use the C ABI.

Key types re-exported from `core/`:

- `DesktopEntry`, `DesktopAppList` from `desktop.zig`
- `Action` from `config.zig` (used as the prefix config type)

### `config.zig` — Configuration

Loads theme and action configs from `~/.config/badi/`. Generates QSS (Qt
Style Sheets) from the theme. No Qt widget imports — only std and JSON.

### `main.zig` — Bootstrap

Wires everything together:

1. Initializes Qt and creates the `QApplication`
2. Creates widgets, loads config, applies theme
3. Detects mode (piped vs apps)
4. Connects signals to callbacks
5. Enters the Qt event loop

## Rules

1. **`core/` never imports `ui/`** — business logic doesn't know about widgets.
2. **`ui/` never imports `core/` directly** — callbacks and window code access
   business data through `context.state()`, not by importing `desktop.zig` or
   `exec.zig`.
3. **`context.zig` is the shared boundary** — both layers import it, but it
   only defines types and a global pointer, no logic.
4. **`config.zig` is standalone** — no imports from `core/` or `ui/`.
