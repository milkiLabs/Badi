# Roadmap

### 1. Re-entrancy guard for all programmatic `SetText` calls

**Why**: `app.setInputText` guards the `textChanged` signal, but only
`enterPrefixMode` uses it. The new `factory.configureInitialFrame` does
`widgets.input.SetText(cfg.default_value)` directly — it fires
`onTextChanged` synchronously, which currently records the query into
`current_query` (a no-op for prompt mode, but a wasted alloc per launch
and a landmine if a non-prompt caller ever sets a default).
**T-shirt**: S.
**Touches**: `ui/factory.zig`, possibly `ui/callbacks/text.zig`.

### 4. `launched-but-failed` exit code

**Why**: `apps.zig`, `prefix.zig`, `url.zig` all ignore the bool return
of `QProcess.StartDetached22`. If `xdg-open` or `sh` is missing, Badi
exits 0 and the user thinks the launch worked. The pattern is already in
`emoji.zig::typeKeysAndExit` (item #6 of the refactor): set `exit_code`
based on what actually succeeded.
**T-shirt**: S.
**Touches**: `modes/{apps,prefix,url}.zig`.

### 5. Make the `: ` emoji trigger configurable

**Why**: It's a hardcoded `const` in `ui/callbacks/text.zig:14`. Some
users want a different trigger (`; `, `/`). A single line in
`config.json` plus a fallback default is enough.
**T-shirt**: S.
**Touches**: `config/actions.zig`, `ui/callbacks/text.zig`.

## Soon (1-2 months)

Real features. Each one is its own short release.

### 7. `clear` action binds to a key (e.g. Ctrl+U)

**Why**: Currently `Ctrl+C` clears (line 41 of `key.zig`). `Ctrl+U` is the
muscle-memory choice for "clear line" in readline/bash. Trivial to add.
**T-shirt**: XS.
**Touches**: `ui/callbacks/key.zig`.

### 8. Action history with ↑/↓ recall

**Why**: The current `prefix` mode reads the input but doesn't keep a
history. Most launchers keep the last N inputs per action and let you
cycle. Reuses `core/piped_sort.zig` if #4 lands, or just a separate
`std.ArrayList([]const u8)` per `Action`.
**T-shirt**: M.
**Touches**: `state/app_state.zig` (new `history` field per action),
`ui/callbacks/key.zig`, `modes/prefix.zig`, a small `config/history.zig`.

### 9. Fuzzy prefix matching in trigger config

**Why**: Right now `trigger` is a fixed string ("g ", "> "). Some users
want regex or glob. The cleanest design is `trigger: []const u8` (current
behavior) and `trigger_kind: enum { exact, regex, prefix }` with a
default of `.exact`. Backward-compatible.
**T-shirt**: M.
**Touches**: `config/actions.zig`, `ui/callbacks/text.zig`,
`core/search.zig` (regex scoring).

### 10. Config schema validation

**Why**: `config/loader.zig` uses `ignore_unknown_fields = true` and
silently returns the default on any parse error. A bad `theme.json`
(typo in a field name, malformed JSON) silently falls back to defaults
with no warning. Add a `std.log.warn` for "unknown field X" and
"parse error: Y" so users can debug.
**T-shirt**: S.
**Touches**: `config/loader.zig`.

### 11. Sort `apps` results by launch frequency

**Why**: The current `apps` mode shows all installed apps in source
order, with substring/acronym matching. Ties on score are broken by
source index, which is the .desktop file name. A tiny `launch_counts`
hashmap (loaded from `~/.local/share/badi/history.json`) that bumps the
score by `log2(count)` re-orders results the way the user expects
("the thing I launch most often comes first even with a vague query").
**T-shirt**: M.
**Touches**: `core/search.zig`, new `core/launch_history.zig`,
`app/exit_code.zig` (increment on success), `ui/model.zig`.

### 12. X11 fallback for the layer shell

**Why**: `ui/wayland.zig` no-ops on X11. On X11 the window is a
`FramelessWindowHint` dialog with `WindowStaysOnTopHint` — usable but
not centered, not over panels, not "above all". The fix is to detect
X11 in `wayland.zig` and call Xlib's `XRaiseWindow` + `_NET_ACTIVE_WINDOW`
to keep it on top and focused. The `wayland_layer_shell.cpp` shim stays
Wayland-only.
**T-shirt**: M. Requires linking libX11.
**Touches**: `wayland_layer_shell.cpp`, new `x11_focus.cpp`, `build.zig`.

### 13. `window-position` config field

**Why**: Always centered on Wayland via the layer shell; on X11 the
Qt default (mouse position) is what you get. A `centered`, `cursor`,
or `top` enum in `theme.json` solves the X11 case and lets Wayland
users override the default.
**T-shirt**: S.
**Touches**: `ui/factory.zig`, `config/theme.zig`.

### 14. `quote-shell-arg` for prefix actions: `argv` mode

**Why**: Right now prefix actions use `sh -c "template %s"`. Some users
want to pass argv directly (e.g. a known program with a known arg
shape). A second field `argv: ?[]const u8` (read as
`argv[0] = $program, argv[1..] = $args` with `%s` substitution in each
arg) covers it.
**T-shirt**: S.
**Touches**: `config/actions.zig`, `modes/prefix.zig`.

### 15. `--no-replace` flag for the single-instance protocol

**Why**: Currently a second Badi always replaces the first. Some users
want to "queue" (the new one waits, the old one closes on Escape).
**T-shirt**: M.
**Touches**: `app/single_instance.zig`, `app/cli.zig`,
`ui/callbacks/replacement.zig`.

## Later (3-6 months)

Bigger work. Each one is its own project.

### 16. New mode: `calc`

**Why**: A calculator launcher is a common ask. Take the current input,
parse it as an arithmetic expression (using a tiny expression parser
built for the job — no `eval()` of shell), format the result, and
launch the same way `print` works in `emoji.zig`. Reuses
`core/search.zig`'s score function for the result (display the result
with a high score so it always tops the list). Score-and-print pattern
is reusable.
**T-shirt**: M.
**Touches**: new `core/calc.zig`, new `modes/calc.zig`,
`state/mode.zig` (new variant), `ui/callbacks/text.zig` (new trigger),
all per-mode dispatch sites.

### 17. New mode: `bookmarks`

**Why**: A `b:foo` (browser bookmark with `foo` as the search key) or
`f:foo` (file search) mode. Bookmarks are loaded from
`~/.local/share/badi/bookmarks.json`. File mode uses `fd`-style search
on a configured root.
**T-shirt**: M each. Two modes, similar shape.
**Touches**: new `modes/{bookmarks,file}.zig`, `state/mode.zig`,
`config/actions.zig` (or a separate `config/sources.zig`).

### 18. AUR / deb / nix packages

**Why**: Currently only the `AppImage` workflow in `docs/appimage.md` is
documented. AUR is the low-hanging fruit (single `PKGBUILD`); deb needs
a `.desktop` file + icon + `dh` rules; nix is a flake. Each is
self-contained.
**T-shirt**: S (AUR), M (deb), M (nix).
**Touches**: `packaging/` (new dir), `docs/`.

### 19. Snapshot tests for `onModelData`

**Why**: `ui/model.zig` is the only file with no unit tests. The Qt
model is the most-fragile contract in the app (it formats strings,
switches on mode, has three return paths per row). A test that
builds a fake `AppState`, sets the mode, and asserts the exact string
returned by `onModelData` for `(row=0, role=DisplayRole)` for each mode
would lock the format down.
**T-shirt**: S.
**Touches**: new test file, maybe a `test/mock_app_state.zig` helper.

### 20. Integration test: full piped-mode flow

**Why**: `zig build test` covers the pure core but not the Qt side. A
test that `fork()`s, sets stdin to a pipe, execs `badi`, writes some
lines, waits for the model to populate, and asserts the visible rows
matches the expected filter would catch regressions in the
`piped_view` ↔ `callbacks/piped` interaction. Requires a `QApplication`
in the test process; works under `xvfb-run`.
**T-shirt**: L. The first integration test is the hardest.
**Touches**: new `integration_test.zig`, CI job (x11 + xvfb).

### 21. Search results: case-insensitive accent folding

**Why**: A user types "jalapeno" and the candidate is "jalapeño". Right
now the score is -1 (no match). A tiny table of NFD/NFC + Latin-to-ASCII
folding (à → a, ñ → n, etc.) makes the search feel right. Build the
folded candidate string once at app load (or lazy on first search).
**T-shirt**: M.
**Touches**: `core/search.zig`, new `core/unicode_fold.zig` (or
a 100-line inline table).

## Future (6+ months)

These need a longer conversation before code.

### 22. Plugin system for modes

**Why**: Six modes is enough to feel the cost of "one more" — every
new mode touches `state/mode.zig`, the dispatch switch, the model, the
view, the key handler, and the status updater. A `Mode` trait with
required methods (`launch`, `displayRow`, `onTextChanged`, `onKeyPress`,
`hasListSource`, `hasBadge`, `resultCount`) and a registration API
would make the next ten modes free. The cost is runtime dispatch
(vtable) instead of a comptime switch — but the per-mode launch is
already a non-inlined function call across files, so the cost is
already paid.
**T-shirt**: L. Refactor + new API + migrate all 6 modes.
**Touches**: a lot. Do it as its own milestone.

### 23. Plugin system for actions

**Why**: The `Action` struct (trigger, name, icon, shell template) is
hardcoded to a shell template. A user might want a Python plugin that
queries a custom API. Same vtable pattern as #22.
**T-shirt**: L. Only after #22.

### 24. Multi-display layer shell support

**Why**: `wayland_layer_shell.cpp` binds to the focused output. For a
multi-monitor setup where Badi was launched from output 2 but the
cursor is on output 1, the window shows on output 1. Sometimes
intentional, sometimes surprising. A `target_output: enum { focused,
primary, named }` config field.
**T-shirt**: M. Mostly a `wl_output` lookup.
**Touches**: `wayland_layer_shell.cpp`, `config/theme.zig`.

### 25. Theme: per-element overrides

**Why**: Right now the theme is a flat list of colors. Power users
want a different background for `prefix` mode, a different accent
when results are empty, etc. A nested config (`input.background`,
`list.item_selected.background`, ...) keeps the loader signature
stable while letting `generateQss` be richer.
**T-shirt**: M.
**Touches**: `config/theme.zig`, `config/style.zig`.

## Open questions

Things I don't have a strong opinion on. Worth discussing before
committing.

### Q1. Embedded emoji slab vs lazy file load?

**The question**: `@embedFile` puts the 200 KB binary in the executable
and is available at process start with no I/O. A lazy `readFile` from
`/usr/share/badi/emoji.bin` keeps the binary small and lets distros
ship emoji as a separate package. The trade-off is "fat single-file
launcher" vs "needs an install step".
**My current lean**: Keep `@embedFile`. The 200 KB is well below the
threshold where it matters, and "one file, runs anywhere" is a
defining property of a launcher.

### Q2. Single binary or split into `badi` + `badi-emoji-data`?

**The question**: Same trade-off as Q1, but at the package level. Split
means a smaller `badi` package and an optional `badi-emoji-data`
package. Nix/AUR users would appreciate this; deb users probably
wouldn't.
**My current lean**: Single package. The optional dep is more
confusing than the 200 KB savings.

### Q3. JSON config vs TOML?

**The question**: Zig 0.16 has a TOML parser in the standard library.
`std.json` is what we use now, and `parseFromSliceLeaky` with
`ignore_unknown_fields` is fine. But TOML is friendlier for humans
(no trailing commas, comment syntax, multi-line strings).
**My current lean**: Stick with JSON. The user pain is in the keys,
not the syntax. A schema doc + a JSON schema file (`badi.schema.json`)
gives editor completion, which is the actual fix.

### Q4. Configurable modes or fixed set?

**The question**: The 18-item refactor's "single switch on AppMode"
design treats modes as a closed set. Plugin-style modes (#22) would
open it. The cost of opening: the dispatch switches (model, view,
status, key) become vtables, and exhaustiveness checks go away.
**My current lean**: Closed set until the 6th mode feels painful.
After that, #22.

### Q5. Hard-coded placeholder texts?

**Why**: "Search apps...", "Type a URL..." etc. are hardcoded in
`ui/callbacks/helpers.zig:10-13`. The Arabic RTL hint in the
environment (user paths) suggests i18n is a real need. A
`tr("...")` shim with a `Locale` lookup is the minimum.
**My current lean**: Wait until someone asks. The cost of a
half-done i18n is worse than no i18n.

## Out of scope (and why)

These come up in roadmap discussions for similar launchers. They
don't fit Badi's design.

- **Wayland-only**: No. `ui/wayland.zig` already has a clear X11
  fallback path (#12). The shim is Wayland-only because that's where
  the protocol complexity lives; the rest of the app is protocol-
  agnostic.
- **DRM/KMS direct rendering**: No. The whole point of Badi is to
  integrate with the desktop (single-instance replacement, clipboard
  via wl-copy, etc.). A standalone KMS render would skip the WM and
  not be a "launcher" anymore.
- **Touch / mobile**: No. The keyboard-driven model is the product.
- **Wayland protocols beyond layer-shell**: No. `wlr-layer-shell` is
  the lowest common denominator that works on wlroots, KDE, and
  GNOME-with-the-extension. Adding more protocols couples us to a
  specific compositor.

## How to read this

- **Now** is what I'd merge next. Each is independent.
- **Soon** is what I'd merge in the next 1-2 release cycles.
- **Later** is a real feature, not a refactor. Each gets its own
  design doc and review.
- **Future** is the right shape but the wrong time. Don't start
  these until the rest is shipped.
- **Open questions** are unresolved. Pull requests that touch these
  should come with a proposal, not just code.

The "Now" list is small on purpose. Six small items, each
independently shippable, is more valuable than three big ones that
block each other.
