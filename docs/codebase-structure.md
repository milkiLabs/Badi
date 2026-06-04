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
│  emoji             │                                │
├────────────────────┴────────────────────────────────┤
│  plugins/  (api, builtin, transitions, util)        │
│  Mode trait + vtable + built-in mode implementations │
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
| `core/mod.zig`          | std only     | Re-exports (`desktop`, `exec`, `filter`, `launch_history`, `search`, `emoji`) |
| `core/desktop/entry.zig`| std only     | `DesktopEntry` struct (parsed `.desktop` file) |
| `core/desktop/parser.zig`| std only    | Parses key/value pairs from `[Desktop Entry]` blocks |
| `core/desktop/xdg.zig`  | std only     | XDG directory enumeration |
| `core/desktop/loader.zig`| std only    | Walks XDG dirs, parses + filters entries, dedupes by `id` |
| `core/desktop/mod.zig`  | std only     | Re-exports `DesktopEntry`, `nameOf`, etc. |
| `core/exec.zig`         | std only     | FreeDesktop exec string parsing, shell quoting |
| `core/filter.zig`       | std only     | Generic fuzzy+substring filter using a comptime accessor |
| `core/launch_history.zig` | std only   | Per-app launch counts persisted to `XDG_DATA_HOME/badi/history.json`; `log2(count)` boost signal for ranking |
| `core/search.zig`       | std only     | Substring search + ranking (`score`, `search`, `searchMapped`, `searchMappedBoosted`, `sortScored`) |
| `core/emoji.zig`        | std only     | Embedded emoji binary slab + search helpers |

All of `core/` is **pure Zig** — no Qt imports. Testable without libqt6zig.

### `ui/` — Qt Widget Manipulation

| File / dir                       | Deps                          | Purpose                                            |
| -------------------------------- | ----------------------------- | -------------------------------------------------- |
| `ui/mod.zig`                     | qt6, state, core, plugins     | Re-exports                                         |
| `ui/factory.zig`                 | qt6, state, config            | Builds widgets, wires signals, applies theme       |
| `ui/view.zig`                    | qt6, state, core              | Filter + selection for the active mode             |
| `ui/model.zig`                   | qt6, state, plugins           | `QAbstractListModel` callbacks (`onModelRowCount`, `onModelData`) — vtable calls |
| `ui/status.zig`                  | qt6, state, plugins           | Status / no-results label updates                  |
| `ui/piped_view.zig`              | qt6, state, core              | Piped mode display helpers                         |
| `ui/callbacks/text.zig`          | qt6, state, plugins, core     | `onTextChanged` — delegates to `app.mode.plugin.onTextChanged` |
| `ui/callbacks/key.zig`           | qt6, state, plugins           | `onKeyPress` — Enter, Esc, arrows, Ctrl-W          |
| `ui/callbacks/click.zig`         | qt6, state, plugins           | `onModelClicked`                                   |
| `ui/callbacks/piped.zig`         | qt6, state, core              | `onStdinActivated`, line buffering                  |
| `ui/callbacks/replacement.zig`   | qt6, state                    | Substring replacement after selection              |
| `ui/callbacks/helpers.zig`       | qt6, state, plugins           | Thin re-export of `plugins/builtin.zig` wrappers   |
| `ui/callbacks/mod.zig`           | qt6, state                    | Re-exports + `SignalCallbacks` struct              |

`ui/` is the only place that imports `qt6`. The `core/filter` and `core/search`
modules are used from `ui/view.zig` and `ui/piped_view.zig`.

### `plugins/` — Mode Trait and Built-in Modes

| File             | Deps                | Purpose                                         |
| ---------------- | ------------------- | ----------------------------------------------- |
| `plugins/api.zig`| std, qt6            | `Mode` trait (function-pointer vtable), `ActiveMode`, `Trigger`, `Context`, `TextResult`, `SelectionSource`, default no-op helpers |
| `plugins/builtin.zig`| std, qt6, state, core | All 6 built-in mode implementations (`apps`, `piped`, `action`, `url`, `prompt`, `emoji`), `modeById`, `all`, and public transition wrappers (`exitToApps`, `enterActionMode`, `enterUrlMode`, `enterEmojiModeTrigger`) |
| `plugins/transitions.zig`| plugins, state | Generic `enterMode(app, active, opts)` and `matchesTrigger(query, prefix)` |
| `plugins/util.zig`| std, qt6, state    | `writeStdout`, `launchDetached` (moved from old `modes/util.zig`) |

The `Mode` trait uses a struct of function pointers. The `Action` (prefix)
mode reads its `Trigger` from the static `all` slice; its per-instance
data (the duplicated `config.Action`) is stored on `AppState.prefixes`
and `AppState.registered_triggers` and pointed to by `ActiveMode.ctx`.

The plugin system is **in-process** — modes are static Zig values
referenced by `*const Mode`. There is no dynamic library loading.

### `state/` — The Shared Boundary

| File             | Deps             | Purpose                                |
| ---------------- | ---------------- | -------------------------------------- |
| `state/mod.zig`  | std, qt6         | Re-exports                            |
| `state/mode.zig` | std              | `AppMode = plugin.ActiveMode` re-export, `PromptConfig`, `EmojiConfig`, `EmojiAction`, `EmojiEntry` |
| `state/widgets.zig` | qt6           | `Widgets` struct (Qt widget handles)   |
| `state/app_state.zig` | std, qt6     | `AppState` — single source of truth. Heap-allocated by `buildState`; `App.state: *AppState` |
| `state/global.zig`  | (none runtime)  | C-ABI bridge: `set(s)` / `get()`       |

`AppState` is heap-allocated by `startup.buildState` so its address is
stable for the whole process. `App.state: *AppState`; `App.destroy`
calls `state.deinit` then `gpa.destroy(self.state)`. The `AppMode`
field is a `plugin.ActiveMode = { plugin: *const Mode, ctx: ?*const anyopaque }`,
giving the rest of the app a single uniform shape (plugin vtable +
opaque per-mode context).

`global` is set once in `app.App.run` and read by Qt callbacks that
use the C ABI.

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

### `app/` — Lifecycle & Wiring

| File             | Deps                | Purpose                                   |
| ---------------- | ------------------- | ----------------------------------------- |
| `app/mod.zig`    | qt6, state, ui, ... | `App` struct: `create` / `run` / `destroy`. `App.state: *AppState`. |
| `app/cli.zig`    | std                 | `parse` (CLI arg parsing) + `parsePromptFlags` |
| `app/startup.zig`| std, qt6, state, plugins | `buildState` (heap-allocates), `resolveInitialMode`, `prepareInitialFrame` |
| `app/exit_code.zig`| std, state, plugins | `resolve(app) u8` — maps state to exit code |
| `app/single_instance.zig` | std, state | Single-instance server check (uses `app.singleInstanceEnabled()`) |

`App` lifecycle:
1. `App.create` — init `QApplication`, load config, build widgets,
   build state (heap-allocate). Stores `*AppState` in `self.state`.
2. `App.run` — sets the global, prepares the initial frame, shows
   the window, runs the event loop, resolves exit code.
3. `App.destroy` — `state.deinit()` → `gpa.destroy(self.state)` →
   `qapp.Delete()` → `qt6.deinit(gpa, argv)`.

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

1. **`core/` never imports `ui/`, `plugins/`, or `state/`** — business
   logic doesn't know about widgets, mode plugins, or shared state.
2. **`plugins/` is the per-mode boundary** — UI hands off via the
   `Mode` vtable on `app.mode.plugin`. Each mode owns its per-instance
   data through `ActiveMode.ctx`.
3. **`ui/` accesses state only through `state.global.get()`** (C-ABI bridge
   inside callbacks; direct field access in normal `ui` functions).
4. **`config/` has no `core/`, `ui/`, or `plugins/` imports** — theme/QSS
   may touch `qt6` only for `QApplication.setStyleSheet`, but that lives
   in `ui/factory`.
5. **`app/` is the only place that knows about `ui/`, `core/`, `config/`,
   `plugins/`, and `state/` together** — wiring layer.
6. **`state/` is the data model** — no UI, no business logic, just data
   + the C-ABI global bridge. The mode-related types (`AppMode`,
   `PromptConfig`, `EmojiConfig`) are re-exports from `state/mode.zig`,
   which itself re-exports `plugin.ActiveMode` and lives here for
   historical reasons (the modes used to be defined in `state/`).
