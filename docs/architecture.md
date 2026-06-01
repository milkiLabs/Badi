# Architecture: Mode Detection and Startup

## Overview

Badi operates in one of **six** modes. Five are auto-detected or explicit,
one (emoji) has two entry points (CLI flag or runtime trigger):

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
│                             load emoji slab (eager)  │
│                             populate list             │
│                             show window               │
│                                                       │
└──────────────────────────────────────────────────────┘
```

`prefix`, `url`, and emoji (mid-session) are **not** initial modes — they're
entered mid-session when the user types a trigger (e.g. `g ` for prefix, a
URL-shaped string for url, or `": "` for emoji). See [modes.md](modes.md).

The two startup paths share everything except the work that only matters in
apps mode (loading `.desktop` files) and the work that only matters in piped
mode (installing the stdin notifier).

## App Lifecycle

The full `App.create` → `App.run` → `App.destroy` sequence is documented in
[app-lifecycle.md](app-lifecycle.md). This document focuses on the **startup**
slice: which mode is chosen and how the first frame is prepared.

Startup flow (in `app.App.run` and `app.startup`):

1. `state.global.set(&self.state)` — install the C-ABI global pointer. Has
   to happen here, not in `create`, because the AppState is moved into
   `self` when `create` returns (a stack-local pointer would dangle).
2. `startup.resolveMode(io, settings)` — see the flowchart above. Returns
   the initial `AppMode`.
3. `startup.prepareInitialFrame(...)` — wires the `QSocketNotifier` for
   piped mode, sets the window title, calls `ui.factory.configureInitialFrame`,
   and does the first filter pass (apps: empty query, piped: status label).
4. `ui.main.Show()` — show the window. Qt invokes `onModelRowCount` /
   `onModelData` to populate the list.
5. `qt6.QApplication.Exec()` — enter the event loop.
6. `app.exit_code.resolve(&self.state)` — pick the exit code.

## Piped Mode

Triggered when stdin is a real pipe (FIFO). Used for `dmenu`-style workflows:

```bash
echo -e "foo\nbar\nbaz" | badi
find / -type f | badi
```

### Startup sequence

1. `resolveMode` sees `stat.kind == .named_pipe` and returns `.piped`.
2. `prepareInitialFrame` shows the window with "Waiting for input…" and
   creates a `QSocketNotifier` on `STDIN_FILENO`, parented to the main
   widget (auto-freed on close). The callback is `ui.callbacks.onStdinActivated`.
3. Enter `QApplication.Exec()`.
4. As data arrives, `onStdinActivated` (in `src/ui/callbacks/piped.zig`):
   - Reads up to 64 KB via `std.posix.read`.
   - Buffers partial lines in `AppState.stdin_pending`.
   - Complete lines are trimmed (CR stripped) and handed to
     `piped_view.appendPipedItem`, which inserts them into the visible
     list at the correct sorted position.
5. User types to filter (the filter runs against the accumulated lines via
   `ui.view.applyFilter`). The user can filter before all lines have arrived.
6. Enter → `modes.piped.launch` writes the selected line to stdout; exit 0.
7. Escape → `app.exit_code = 1`, window closes.

### Key files

- `src/app/startup.zig` — notifier creation, status label
- `src/ui/callbacks/piped.zig` — stdin reading pipeline
  - `onStdinActivated`, `appendBytes`, `appendLine`, `flushTrailingLine`
- `src/ui/piped_view.zig` — incremental list population
  - `appendPipedItem`, `renderPipedAppendBatch`

## Apps Mode

Triggered when stdin is NOT a pipe (terminal, `/dev/null`, file redirect).
Used for the primary desktop app launcher:

```bash
badi                    # from terminal
$mod+p                  # from Sway keybinding (stdin = /dev/null)
```

### Startup sequence

1. `resolveMode` sees `stat.kind != .named_pipe` and returns `.apps`.
2. **During `buildState`** (called from `App.create`): desktop apps are
   loaded synchronously via `core.desktop.loadDesktopApps` and stored in
   `app.app_list`. This way, by the time `Show()` is called, the list is
   fully populated.
3. `prepareInitialFrame` calls `ui.view.applyFilter(app, "")` which fills
   `visible_indices` with all source rows in order, resets the Qt model,
   and selects row 0.
4. Show window — fully interactive from the first frame.

### Why synchronous loading?

Loading `.desktop` files is a blocking filesystem scan (~200+ files). Running
it synchronously in `buildState` (before `Show()`) means the window is fully
responsive the moment it appears. The scan typically completes in under
100 ms on modern hardware with warm disk caches.

### Key files

- `src/app/startup.zig` — synchronous desktop loading
  - `buildState` → `core.desktop.loadDesktopApps`
- `src/ui/view.zig` — first-paint filter and selection
  - `applyFilter`, `selectModelRow`
- `src/core/desktop/loader.zig` — the actual file walker
  - `loadDesktopApps`

## Prefix Mode (Mid-Session)

Entered when the user types a configured trigger (e.g. `g ` for Google
search). The active prefix is stored as a `config.Action` in
`AppMode.prefix`. **Not** an initial mode — see
[modes.md](modes.md#prefix-mode) for the full flow.

### Key files

- `src/ui/callbacks/text.zig` — trigger detection in `onTextChanged`
- `src/ui/callbacks/helpers.zig` — `enterPrefixMode`, `exitToApps`
- `src/modes/prefix.zig` — `launch`: shell-template composition + spawn

## URL Mode (Mid-Session)

Entered when the user types something that looks like a URL (e.g.
`example.com`). The `url` variant in `AppMode` replaces the old
`name == "Browser"` string hack. **Not** an initial mode — see
[modes.md](modes.md#url-mode) for details.

### Key files

- `src/utils/url.zig` — `isUrl(text)` heuristic
- `src/ui/callbacks/text.zig` — auto-detect and switch into url mode
- `src/modes/url.zig` — `launch`: prepend `https://` if needed, `xdg-open`
- `src/ui/callbacks/helpers.zig` — `enterUrlMode`

## Prompt Mode

Entered when `--prompt` is passed on the command line. The user types into
the input field; whatever they type is written to stdout on Enter. Used by
shell scripts that need a free-form text answer. See
[prompt-mode.md](prompt-mode.md) for the full reference.

### Startup sequence

1. `cli.parse` sees `--prompt` (and optionally `--default`, `--password`,
   `--allow-empty`) and builds a `state.PromptConfig`.
2. `resolveMode` returns `.prompt` unconditionally.
3. `buildState` skips desktop loading (the list is hidden anyway).
4. `ui.factory.build` sees `prompt != null` and:
   - Sets `main.SetFixedSize2(width, 80)` for a single-row window.
   - Sets the badge label (if any) and shows it.
   - Pre-fills the input + `SelectAll` (if `--default` was given).
   - Toggles `SetEchoMode(Password)` if `--password` was given.
   - Hides the `QListView` and `no_results` label — the layout treats
     hidden children as zero-size, so the window collapses to the input
     row.
5. `ui.factory.configureInitialFrame` sets the window title
   (`Badi` or `Badi — <label>`) and focuses the input.
6. Show window. `onModelRowCount` returns 0 for `.prompt` — the list is
   empty. No `QSocketNotifier` is installed (stdin is ignored).
7. On Enter, `modes.prompt.launch` writes `text + "\n"` to stdout, sets
   `exit_code = 0`, and closes the window.
8. On Escape, `ui.callbacks.onKeyPress` sets `exit_code = 1` and closes.

### Key files

- `src/app/cli.zig` — `parse` and `parsePromptFlags`
- `src/ui/factory.zig` — `build(arena, theme, prompt)` — prompt-mode chrome
- `src/ui/factory.zig` — `configureInitialFrame` — title + prefill + focus
- `src/modes/prompt.zig` — `launch`: write to stdout, close
- `src/ui/callbacks/key.zig` — Enter, Escape, Ctrl-W, Backspace
- `src/ui/callbacks/text.zig` — prompt-mode short-circuit in `onTextChanged`

## Exit Codes

Resolved by `src/app/exit_code.zig::resolve` after the event loop exits.
If the launch function set `exit_code`, that wins; otherwise a default is
picked per mode.

| Condition                            | Exit code |
| ------------------------------------ | --------- |
| Item selected (Enter/double-click)   | 0         |
| Escape in piped mode                 | 1         |
| Escape in prompt mode                | 1         |
| Escape in apps / prefix / url mode   | 0         |
| Window closed via window manager     | 0         |

Defaults per mode: `piped`, `prompt`, and `emoji` → 1 (cancelled); `apps`,
`prefix`, `url` → 0 (window closed normally).

## Emoji Mode

Triggered by the `--emoji` CLI flag (initial mode) or by typing `": "` in
apps mode (mid-session). Renders the pre-packed emoji binary slab in the
list. Selection dispatches to the configured action — see
[emoji-mode.md](emoji-mode.md) for the full reference.

The data is a pre-packed binary blob embedded at compile time:

```
┌──────────────┬──────────────────┬──────────────────────┐
│ Header (16B) │ Blob (157 KB)    │ Records (45 KB)      │
│ magic, ver,  │ glyph/name/kw    │ 1914 × 24-byte       │
│ count        │ strings, null    │ (glyph_off/len,      │
│              │ separated        │  name_off/len,       │
│              │                  │  kw_off/len)         │
└──────────────┴──────────────────┴──────────────────────┘
```

The blob is generated by `scripts/gen-emoji.zig` from vendored sources
(muan/unicode-emoji-json + muan/emojilib). The build step `zig build
gen-emoji` regenerates `src/core/emoji/data/emoji.bin`; the file is
committed so consumers don't need to regenerate.

### Startup sequence (initial)

1. `cli.parse` sees `--emoji` (and optionally `--copy`, `--print`, or
   `--type`) and builds a `state.EmojiConfig`.
2. `resolveMode` returns `.emoji` unconditionally (when `--emoji` is
   set, even stdin being a pipe is ignored).
3. `buildState` pre-loads the emoji slab via `core.emoji.loadEmojis`
   and stores it in `app.emojis`.
4. `configureInitialFrame` sets the window title to `"Badi — Emoji"`.
5. Show window. Filter is applied to the emoji entries; the user can
   start typing immediately.

### Startup sequence (mid-session, `": "` trigger)

1. User is in apps mode and types `": "`.
2. `ui.callbacks.onTextChanged` detects the hardcoded `": "` prefix
   before any user-configured prefix triggers.
3. Calls `helpers.enterEmojiMode` which switches `app.mode` to
   `.emoji`, clears the input, and reapplies the filter (which now
   targets emoji entries).
4. On Enter, `modes.emoji.launch` runs the configured action.

### Key files

- `src/core/emoji/{mod,entry,loader}.zig` — slab loader + entry accessors
- `src/core/emoji/data/emoji.bin` — generated binary, `@embedFile` target
- `scripts/gen-emoji.zig` — generator (run via `zig build gen-emoji`)
- `src/app/cli.zig` — `--emoji` parsing
- `src/modes/emoji.zig` — action dispatch (copy / print / type_keys)
- `src/ui/callbacks/text.zig` — `": "` trigger check
- `src/ui/callbacks/helpers.zig` — `enterEmojiMode`
