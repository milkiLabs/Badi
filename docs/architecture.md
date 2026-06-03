# Architecture: Mode Detection and Startup

This document describes the **startup flow** — which mode is chosen and
how the first frame is prepared. Per-mode behavior lives in
[modes.md](modes.md); the per-mode internals (piped stdin pipeline,
prompt flags, emoji data) live in the per-feature deep-dives linked
from the [docs README](README.md).

## Overview

Badi operates in one of **six** modes. Four are **initial modes**
(chosen at startup) and two are **mid-session modes** (entered by
typing a trigger):

| Mode      | Initial? | Entered by                                                  |
| --------- | -------- | ----------------------------------------------------------- |
| `apps`    | yes      | stdin is not a pipe and no `--prompt`/`--emoji`             |
| `piped`   | yes      | `stdin.stat().kind == .named_pipe`                          |
| `prompt`  | yes      | `--prompt` flag on the command line                         |
| `emoji`   | yes      | `--emoji` flag on the command line                         |
| `prefix`  | no       | typing a configured trigger (e.g. `g `) in `apps` mode      |
| `url`     | no       | typing something that `isUrl(text)` recognizes in `apps`    |

`prefix`, `url`, and emoji (mid-session) are **not** initial modes —
they're entered mid-session by typing a trigger. See
[modes.md](modes.md) for the full transition rules and the
"add a new mode" recipe.

```
┌──────────────────────────────────────────────────────┐
│                    Badi Startup                       │
├──────────────────────────────────────────────────────┤
│                                                       │
│  --prompt flag present?                                │
│       │                                               │
│       ├── YES ──→ Prompt Mode                        │
│       │            shrink window to 80px              │
│       │            hide list, show only input + label │
│       │            ignore stdin                       │
│       │                                               │
│       └── NO ───┐                                     │
│                ▼                                     │
│  --emoji flag present?                                │
│       │                                               │
│       ├── YES ──→ Emoji Mode (initial)               │
│       │            load pre-packed binary slab       │
│       │            show window, allow filtering       │
│       │                                               │
│       └── NO ───┐                                     │
│                ▼                                     │
│       stdin.stat().kind == .named_pipe?              │
│                │                                      │
│                ├── YES ──→ Piped Mode                │
│                │            show window immediately  │
│                │            QSocketNotifier on stdin  │
│                │            stream lines as they arrive│
│                │                                      │
│                └── NO ───→ Apps Mode                 │
│                             load .desktop files sync  │
│                             populate list             │
│                             show window               │
│                                                       │
└──────────────────────────────────────────────────────┘
```

The two startup paths share everything except the work that only matters
in apps mode (loading `.desktop` files) and the work that only matters
in piped mode (installing the stdin notifier).
The emoji binary remains embedded in the executable, but its heap entry
index is allocated only when emoji mode is entered.

## App Lifecycle

The full `App.create` → `App.run` → `App.destroy` sequence is documented
in [app-lifecycle.md](app-lifecycle.md). This document focuses on the
**startup** slice: which mode is chosen and how the first frame is
prepared.

Startup flow (in `app.App.run` and `app.startup`):

1. `state.global.set(&self.state)` — install the C-ABI global pointer.
   This happens here, not in `create`, because the AppState is moved
   into `self` when `create` returns (a stack-local pointer would
   dangle).
2. `startup.buildState` (called from `create`) has already resolved
   `app_state.mode`; `App.run` reads it as the single source of truth.
   It also loads the per-app launch history from
   `$XDG_DATA_HOME/badi/history.json` (failures are swallowed — the
   launcher is still useful with an empty history).
3. `startup.prepareInitialFrame(...)` — wires the `QSocketNotifier` for
   piped mode, sets the window title, calls
   `ui.factory.configureInitialFrame`, and does the first filter pass
   (apps: empty query, piped: status label).
4. `ui.main.Show()` — show the window. Qt invokes `onModelRowCount` /
   `onModelData` to populate the list.
5. `qt6.QApplication.Exec()` — enter the event loop.
6. `app.exit_code.resolve(&self.state)` — pick the exit code. For
   successful app launches, this is also where the launch history
   gets incremented and re-saved (see
   [launch-history.md](launch-history.md)).

## Exit Codes

Resolved by `src/app/exit_code.zig::resolve` after the event loop exits.
If the launch function set `exit_code`, that wins; otherwise a default
is picked per mode.

| Condition                            | Exit code |
| ------------------------------------ | --------- |
| Item selected (Enter/double-click)   | 0         |
| Escape in piped mode                 | 1         |
| Escape in prompt mode                | 1         |
| Escape in apps / prefix / url mode   | 0         |
| Window closed via window manager     | 0         |

Defaults per mode: `piped`, `prompt`, and `emoji` → 1 (cancelled);
`apps`, `prefix`, `url` → 0 (window closed normally).
