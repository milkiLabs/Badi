# Codebase Structure: Core vs UI Separation

Badi separates business logic from Qt widget manipulation. This document
explains the layering, what lives where, and the rules that keep the boundary
clean.

## Layer Diagram

```
┌─────────────────────────────────────────────────────┐
│                    src/main.zig                     │
│        Thin shim → app.App.create + run             │
├────────────────────┬────────────────────────────────┤
│      core/         │            ui/                 │
│  Pure logic,       │  Qt widget manipulation,       │
│  no Qt deps        │  signal callbacks              │
├────────────────────┼────────────────────────────────┤
│  desktop/          │  callbacks/  (text, key,        │
│    entry, parser,  │    click, piped, helpers)      │
│    xdg, loader     │  factory, view, model,         │
│  filter            │    status, piped_view          │
│  exec              │                                │
│  launch_history    │                                │
│  search            │                                │
├────────────────────┼────────────────────────────────┤
│   modes/  (apps, piped, prefix, url, prompt)        │
│   Per-mode action dispatch (modes that need it)     │
├────────────────────┴────────────────────────────────┤
│  state/  (AppState, AppMode, Widgets, global ptr)   │
│       Shared state — the glue layer                 │
├─────────────────────────────────────────────────────┤
│  config/  (paths, theme, actions, style)            │
│  JSON config loading + QSS generation               │
├─────────────────────────────────────────────────────┤
│  app/  (cli, startup, App lifecycle, exit_code)     │
│  Wiring, process bootstrap, event loop              │
├─────────────────────────────────────────────────────┤
│  utils/  (url helpers)                              │
└─────────────────────────────────────────────────────┘
```

## Module Responsibilities

### `core/` — Business Logic

| File / dir              | Deps         | Purpose                                       |
| ----------------------- | ------------ | --------------------------------------------- |
| `core/mod.zig`          | std only     | Re-exports (`desktop`, `exec`, `filter`, `launch_history`, `search`) |
| `core/desktop/entry.zig`| std only     | `DesktopEntry` struct (parsed `.desktop` file) |
| `core/desktop/parser.zig`| std only    | Parses key/value pairs from `[Desktop Entry]` blocks |
| `core/desktop/xdg.zig`  | std only     | XDG directory enumeration |
| `core/desktop/loader.zig`| std only    | Walks XDG dirs, parses + filters entries, dedupes by `id` |
| `core/desktop/mod.zig`  | std only     | Re-exports `DesktopEntry`, `nameOf`, etc. |
| `core/exec.zig`         | std only     | FreeDesktop exec string parsing, shell quoting |
| `core/filter.zig`       | std only     | Generic fuzzy+substring filter using a comptime accessor |
| `core/launch_history.zig` | std only   | Per-app launch counts persisted to `XDG_DATA_HOME/badi/history.json`; `log2(count)` boost signal for ranking |
| `core/search.zig`       | std only     | Substring search + ranking (`score`, `search`, `searchMapped`, `searchMappedBoosted`, `sortScored`) |

All of `core/` is **pure Zig** — no Qt imports. Testable without libqt6zig.

### `ui/` — Qt Widget Manipulation

| File / dir                       | Deps                          | Purpose                                            |
| -------------------------------- | ----------------------------- | -------------------------------------------------- |
| `ui/mod.zig`                     | qt6, state, core, modes       | Re-exports                                         |
| `ui/factory.zig`                 | qt6, state, config            | Builds widgets, wires signals, applies theme       |
| `ui/view.zig`                    | qt6, state, core              | Filter + selection for apps mode (uses `core.filter`) |
| `ui/model.zig`                   | qt6, state                    | `QAbstractListModel` callbacks (`onModelRowCount`, `onModelData`) |
| `ui/status.zig`                  | qt6, state                    | Status / no-results label updates                  |
| `ui/piped_view.zig`              | qt6, state                    | Piped mode display helpers                         |
| `ui/callbacks/text.zig`          | qt6, state, core, modes       | `onTextChanged` — prefix trigger, URL detect       |
| `ui/callbacks/key.zig`           | qt6, state, modes             | `onKeyPress` — Enter, Esc, arrows, Ctrl-W          |
| `ui/callbacks/click.zig`         | qt6, state                    | `onModelClicked`                                   |
| `ui/callbacks/piped.zig`         | qt6, state                    | `onStdinActivated`, line buffering                  |
| `ui/callbacks/helpers.zig`       | qt6, state                    | Shared helpers (selection read, etc.)              |
| `ui/callbacks/mod.zig`           | qt6, state                    | Re-exports + `SignalCallbacks` struct              |

`ui/` is the only place that imports `qt6`. The `core/filter` module is used
from `ui/view.zig` to drive the model.

### `state/` — The Shared Boundary

| File             | Deps             | Purpose                                |
| ---------------- | ---------------- | -------------------------------------- |
| `state/mod.zig`  | std, qt6         | Re-exports                            |
| `state/mode.zig` | std              | `AppMode` tagged union (5 variants), `PromptConfig` |
| `state/widgets.zig` | qt6           | `Widgets` struct (Qt widget handles)   |
| `state/app_state.zig` | std, qt6     | `AppState` — single source of truth    |
| `state/global.zig`  | (none runtime)  | C-ABI bridge: `set(s)` / `get()`       |

`AppMode` variants:
- `apps` — desktop app launcher
- `piped` — stdin lines
- `prefix: config.Action` — runs a shell action with `%s` substituted
- `url` — opens as `https://…` in the default browser
- `prompt: PromptConfig` — pure prompt, no list source

`global` is set once in `app.App.run` (after the AppState is in its final
location) and read by Qt callbacks that use the C ABI.

### `config/` — Configuration

| File              | Deps       | Purpose                                    |
| ----------------- | ---------- | ------------------------------------------ |
| `config/mod.zig`  | std, qt6   | Re-exports                                 |
| `config/paths.zig`| std        | `resolveConfigDir`                         |
| `config/theme.zig`| std        | `loadTheme` (parses theme.json)            |
| `config/actions.zig` | std      | `loadActions` (parses actions.json)        |
| `config/style.zig`| std, qt6   | `generateQss(theme)` (parses `{{expr}}`)   |

No Qt widget imports in `config/` — only `qapplication.setStyleSheet` in
`ui/factory.applyTheme` which lives in `ui/`.

### `modes/` — Per-Mode Action Dispatch

Each mode that needs custom launch/exit behavior has its own file:

| File            | Mode   | Purpose                              |
| --------------- | ------ | ------------------------------------ |
| `modes/mod.zig` | (all)  | `dispatch(action: LaunchAction) u8`  |
| `modes/apps.zig` | apps  | `core.exec.parseExec` → `core.exec.spawn` |
| `modes/piped.zig`| piped | Logs the line to stdout, returns 0   |
| `modes/prefix.zig`| prefix | `core.prefix.compose` + `core.exec.spawn` |
| `modes/url.zig`  | url    | Prepends `https://` if no scheme, then `core.exec.spawn` |
| `modes/prompt.zig`| prompt | Prints a status line, returns 0      |

`modes/mod.zig` uses a direct `switch` on `app.mode` (not a vtable), because
Zig can't easily coerce heterogeneous function literals to a single vtable
type.

### `app/` — Lifecycle & Wiring

| File             | Deps                | Purpose                                   |
| ---------------- | ------------------- | ----------------------------------------- |
| `app/mod.zig`    | qt6, state, ui, ... | `App` struct: `create` / `run` / `destroy` |
| `app/cli.zig`    | std                 | `parse` (CLI arg parsing) + `parsePromptFlags` |
| `app/startup.zig`| std, qt6, state     | `buildState`, `resolveMode`, `prepareInitialFrame` |
| `app/exit_code.zig`| std, state        | `resolve(app) u8` — maps state to exit code |

`App` lifecycle:
1. `App.create` — init `QApplication`, load config, build widgets, build state.
   **Does not set the global** (the AppState is still a local).
2. `App.run` — sets the global (now in final stack frame), resolves mode,
   shows window, runs event loop, resolves exit code.
3. `App.destroy` — `state.deinit()` → `qapp.Delete()` → `qt6.deinit(gpa, argv)`.

### `utils/`

| File          | Deps | Purpose                       |
| ------------- | ---- | ----------------------------- |
| `utils/url.zig` | std | `looksLikeUrl`, `prependScheme` |

### `main.zig` — Entry Point

7-line shim:
1. `app.cli.parse(...)` for settings
2. `app.App.create(...)` for the lifecycle object
3. `instance.run()` — handles everything else

## Rules

1. **`core/` never imports `ui/`** — business logic doesn't know about widgets.
2. **`modes/` is the per-mode boundary** — UI hands off via `modes.dispatch`.
3. **`ui/` accesses state only through `state.global.get()`** (C-ABI bridge
   inside callbacks; direct field access in normal `ui` functions).
4. **`config/` has no `core/` or `ui/` imports** — theme/QSS may touch `qt6`
   only for `QApplication.setStyleSheet`, but that lives in `ui/factory`.
5. **`app/` is the only place that knows about `ui/`, `core/`, `config/`,
   `modes/`, and `state/` together** — wiring layer.
6. **`state/` is the data model** — no UI, no business logic, just data + the
   C-ABI global bridge.
