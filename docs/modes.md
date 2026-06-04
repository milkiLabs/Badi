# Modes Reference

Badi has six modes. Three are **initial modes** (chosen at startup);
three are **mid-session modes** (entered by typing in apps mode).

Modes are first-class plugin values: each one is a `*const
plugin.Mode` defined in `src/plugins/builtin.zig`, registered in
the `all` slice, and looked up by id via `builtin.modeById`. The
active mode is `AppState.mode: plugin.ActiveMode` — a `*const Mode`
plus an optional per-instance `ctx: ?*const anyopaque`.

```zig
pub const AppMode = plugin.ActiveMode;  // { plugin: *const Mode, ctx: ?*const anyopaque }
```

| Mode    | Initial? | Entered by                                                  | Exits to  |
| ------- | -------- | ----------------------------------------------------------- | --------- |
| `apps`  | yes      | `stdin` is not a pipe, no `--prompt`/`--emoji`              | —         |
| `piped` | yes      | `stdin.stat().kind == .named_pipe`                          | —         |
| `prompt`| yes      | `--prompt` flag on the command line                         | —         |
| `emoji` | yes      | `--emoji` flag on the command line                          | —         |
| `action`| no       | typing a configured trigger (e.g. `g `) in `apps` mode      | `apps`    |
| `url`   | no       | typing something that `isUrl(text)` recognizes in `apps`    | `apps`    |

## How a mode picks its launch

`Enter` and double-click both call `app.mode.plugin.launch(app,
app.mode.ctx)`. Direct vtable call, not a switch — the dispatch
table lives in the `Mode` struct itself, so adding a new mode
doesn't touch this site at all.

Each mode's `launch` function is the single point that turns a user
action into a side effect. Adding a new mode = add a `*const Mode`
value in `plugins/builtin.zig`, append it to `all`, and (if it's an
initial mode) add a branch in `resolveInitialMode`. That's it —
the dispatch site doesn't change.

## The `Mode` trait

`src/plugins/api.zig` defines `api.Mode`, a struct of function
pointers that fully describes a mode's behavior. Every required
field is a `*const fn (...)`; the optional ones are `?*const fn = null`
and get sane defaults (`noFilter`, `noLaunch`, `defaultResultCount`,
`emptyDisplayRow`).

| Field | Purpose |
|---|---|
| `id` | Stable string id; used in logs and `modeById` lookups. |
| `name` | Human-readable name (e.g. for `--help` output). |
| `placeholder` | Default placeholder text for the input field. |
| `has_list_source` | Drives list visibility, the no_results label, and whether `filter` runs. |
| `selection_source` | `none` / `apps` / `piped` / `emoji` — declarative hint for `currentSelectionData`. |
| `badgeText` | Returns the badge label, or `null` for no badge. |
| `emptyText` | Returns the no_results label. |
| `resultCount` | Number of rows the Qt model exposes. |
| `displayRow` | Cell text for `(row, DisplayRole)`; returns a `QVariant`. |
| `filter` | Fills `app.visible_indices` (and `app.piped_visible_scores` if needed). |
| `launch` | What to do on Enter / double-click. |
| `onTextChanged` | Per-keystroke hook; returns `handled` or `continue_filter`. |
| `beforeEnter` | Called before a mode becomes active; return `false` to abort. |
| `canExitToDefault` | `true` if Esc/Backspace/Ctrl-W-on-empty exits to apps. |
| `isCancelable` | `true` if Esc closes the window with exit code 1. |
| `singleInstance` | Opt in to the single-instance replacement socket. |

`api.ActiveMode` wraps the plugin pointer with an optional `ctx` —
a caller-owned pointer to per-instance state (a `config.Action` for
prefix mode, a `PromptConfig` for prompt mode, one of two
`EmojiConfig`s on `AppState` for the two emoji entry paths).

`api.Trigger` pairs a literal trigger string with the
`ActiveMode` it should activate; `AppState.registered_triggers` is
the list the apps mode's `onTextChanged` iterates.

## Per-mode details

### Apps mode

**Source:** `plugins/builtin.zig::apps`

Reads the selected `DesktopEntry` from the source list, parses its
`Exec=` string with `core.exec.parseExec`, and launches via
`QProcess.StartDetached22` so the launched app survives Badi's exit.

The "selected" data is resolved by `AppState.currentSelectionData()`,
which dereferences `selected_index` → `visible_indices` → `app_list` to
return the right `exec` string along with the app's stable id
(`desktop.idOf`) for launch history bookkeeping. Pure data — no Qt
access.

**Ranking.** A successful launch (`exit_code == 0`) bumps the app's
count in `$XDG_DATA_HOME/badi/history.json`. The count is fed back
into the next session's ranking as a small additive boost
(`log2(count)`) on top of the substring/acronym match score. With
an empty query, the list reorders by history alone. See
[launch-history.md](launch-history.md) for the storage format and
the rationale for a weak signal.

**`onTextChanged`.** Owns the prefix-trigger loop: the hardcoded
`: ` emoji trigger, the user-configured prefix triggers (in
`app.registered_triggers`), and URL auto-detect via
`utils.url.isUrl`. Matches transition to `.handled` (don't
re-filter) and URL detection to `.continue_filter` (re-filter in
url mode).

### Piped mode

**Source:** `plugins/builtin.zig::piped`

Reads the selected line from `piped_items`, writes `line + "\n"` to
stdout, and closes the window. The shell pipe on the other end captures
the output.

The async stdin pipeline that fills `piped_items` lives in
`ui/callbacks/piped.zig` and is documented in
[piped-mode.md](piped-mode.md).

### Action (prefix) mode

**Source:** `plugins/builtin.zig::action`

Triggered when the user types a configured trigger (e.g. `g `).
The active trigger's `config.Action` is stored in the
`ActiveMode.ctx`. The input field is cleared and shows a badge
with the action's icon and name.

On Enter: `actionLaunch` reads the query, then dispatches on
`cfg.kind`:

- `.shell` (default) — shell-quote the query, substitute `%s` in
  the template, run via `sh -c "..."` (detached).
- `.argv` — substitute `%s` in each arg, run via
  `QProcess.StartDetached22` (no shell).
- `.http` — substitute `%s` (URL-encoded) in the URL, run via
  `curl -sS -X METHOD ...` (detached). Response body goes to
  stdout.
- `.script` — run the script with the query as `$1` (no shell).

See [user-docs/actions.md](user-docs/actions.md) for config
examples and the kind schema.

### URL mode

**Source:** `plugins/builtin.zig::url`

Entered when `utils.url.isUrl(text)` returns true (heuristic:
has a scheme, is `localhost[:port]`, or has a `tld` of 2+ letters
with no spaces).

On Enter:
1. Read the query from the input.
2. If no `http://` or `https://` prefix, prepend `https://`.
3. Run `xdg-open <url>` (detached).

**`onTextChanged`.** If the new text is no longer a URL, revert to
apps mode via `transitions.enterMode` (returns `.continue_filter`).

### Prompt mode

**Source:** `plugins/builtin.zig::prompt`

Entered only via the `--prompt` CLI flag. The input field is the
answer, not a launcher query. The list is hidden and the window
shrinks to 80 px tall.

On Enter: if the input is empty and `!allow_empty`, do nothing
(keep the window open). Otherwise write `text + "\n"` to stdout and
close. On Escape: close with exit code 1.

See [prompt-mode.md](prompt-mode.md) for the full flag reference.

### Emoji mode

**Source:** `plugins/builtin.zig::emoji`

Entered via the `--emoji` CLI flag (initial) or by typing `": "`
mid-session in apps mode. The list is the full Unicode emoji set
(1914 entries, no skin tone variants) loaded from a pre-packed
binary slab. Two `EmojiConfig`s live on `AppState` (`emoji_cli_context`
for `--emoji`, `emoji_trigger_context` for `: `); the
`ActiveMode.ctx` points at the right one and `emojiCanExitToDefault` /
`emojiIsCancelable` distinguish the two paths.

On Enter, dispatches to the configured `EmojiAction`:

- `.copy` (default) — `wl-copy` → stdout fallback
- `.print` — write the glyph to stdout, exit 0
- `.type_keys` — `wtype` (falls back to `.copy`)

On Escape: close with exit code 1 (cancelled) when entered via
`--emoji`. When entered via `: `, Escape exits to apps.

See [emoji-mode.md](emoji-mode.md) for the full flag reference and
data format details.

## How mode transitions happen

All transitions go through `plugins/transitions.zig::enterMode`,
which:

1. Runs the new mode's `beforeEnter` hook (if any) and aborts on
   `false`.
2. Sets `app.mode = active`.
3. Updates the badge (calls `app.badgeText()` and shows/hides
   the widget).
4. Sets the placeholder.
5. Optionally clears the input (`clear_input = true`).
6. Optionally re-filters (`re_filter = true`).

The four public transition helpers in
`plugins/builtin.zig` (re-exported by
`ui/callbacks/helpers.zig`) pick the right `enterMode` options:

| Helper | Active mode | `clear_input` | `re_filter` |
|---|---|---|---|
| `exitToApps(app)` | `apps` | no | yes |
| `enterActionMode(app, active)` | caller-supplied (prefix action) | yes | yes |
| `enterUrlMode(app)` | `url` | no | no |
| `enterEmojiModeTrigger(app)` | `emoji` (trigger entry) | no | yes |

### `apps` → `action` (typed prefix trigger)

In `appsTextChanged` (`plugins/builtin.zig`), iterate
`app.registered_triggers` and check `matchesTrigger(query,
trigger.text)`. On a match: `enterActionMode` switches to that
trigger's `ActiveMode` (carrying the `config.Action` in `ctx`),
clears the input, and re-filters.

### `apps` → `url`

In `appsTextChanged`, after the trigger loop, check
`url.isUrl(query)`. If true, `enterUrlMode` switches to url mode
(no filter — the url mode's `onTextChanged` runs it).

### `apps` → `emoji`

Hardcoded `: ` trigger (the only one in `appsTextChanged` that
isn't user-configured). `enterEmojiModeTrigger` switches to the
trigger-entry `EmojiConfig` and re-filters.

### `action` / `url` / `emoji` (trigger) → `apps`

Called in three places, all in `onKeyPress`:

- `Escape` (when `canExitToDefault` is true): `exitToApps`
- `Backspace` on empty input: `exitToApps`
- `Ctrl+W` on empty input: `exitToApps`

`exitToApps` hides the badge, restores the apps placeholder, and
re-filters with an empty query.

### `url` → `apps` (on backspace out)

Special case: if the user is in `url` mode and the new text is no
longer a URL, revert to apps mode. This is in the `url` mode's
`onTextChanged` (`urlTextChanged` in `plugins/builtin.zig`):

```zig
if (!url_util.isUrl(query)) {
    transitions.enterMode(app, .{ .plugin = &apps }, .{});
}
return .continue_filter;
```

### `prompt` / `piped` / `emoji` (cli) → cancelled

`isCancelable` is true for these. `Escape` in `onKeyPress` closes
the window with exit code 1.

## Adding a new mode

1. Add a `*const api.Mode` value in `src/plugins/builtin.zig` with
   at least `id`, `name`, `placeholder`, `has_list_source`,
   `selection_source`, `resultCount`, `displayRow`, `filter`,
   `launch` populated. Append it to the `all` slice so
   `modeById` can find it.
2. If the mode needs per-instance state, add a `*Config` field on
   `AppState` (next to `prompt_context`, `emoji_cli_context`,
   `emoji_trigger_context`) and cast the `*const anyopaque` ctx to
   that type in a small helper at the top of `builtin.zig`.
3. If the mode is an initial mode, add a branch in
   `resolveInitialMode` (`src/app/startup.zig`).
4. If the mode is triggered by typing, add a `Trigger` to
   `app_state.registered_triggers` in `buildState`, and a branch
   in `appsTextChanged` (or add a new transition helper if the
   trigger is hardcoded like `: `).
5. If the mode needs new CLI flags, add them to `src/app/cli.zig`.

That's it. The 8 dispatch sites (model, view, status, text, key,
helpers, startup, exit_code) all route through the vtable — none
of them need to know about your new mode.

## Source Files

| File                              | Purpose                                              |
| --------------------------------- | ---------------------------------------------------- |
| `src/plugins/api.zig`             | The `Mode` trait, `ActiveMode`, `Trigger`, default no-op helpers |
| `src/plugins/builtin.zig`         | All 6 built-in modes + handlers + `modeById` + public transition wrappers |
| `src/plugins/transitions.zig`     | Generic `enterMode` + `matchesTrigger`               |
| `src/plugins/util.zig`            | `writeStdout` + `launchDetached` (shared by mode handlers) |
| `src/state/mode.zig`              | `AppMode = plugin.ActiveMode` re-export; `PromptConfig`, `EmojiConfig` |
| `src/state/app_state.zig`         | `mode`, `prefixes`, `registered_triggers`, per-instance state, plugin-delegate methods. Heap-allocated. |
| `src/core/emoji/`                 | Pre-packed binary slab + loader                      |
| `src/ui/callbacks/text.zig`       | `onTextChanged` — single vtable call                  |
| `src/ui/callbacks/key.zig`        | `onKeyPress` — Enter, Esc, arrows, Ctrl-W; reads `canExitToDefault` / `isCancelable` via vtable |
| `src/ui/callbacks/helpers.zig`    | Thin re-export of the `plugins/builtin.zig` transition wrappers |
| `src/utils/url.zig`               | `isUrl(text)` heuristic                              |
| `src/app/startup.zig`             | `resolveInitialMode` (plugin lookups), `prepareInitialFrame` |
| `src/app/cli.zig`                 | `--prompt` and `--emoji` flag parsing                |
| `src/app/exit_code.zig`           | Id-based default exit code                           |
| `src/app/single_instance.zig`     | Single-instance check via `app.singleInstanceEnabled()` |
| `src/app/single_instance.zig`     | `enabled(app)` — calls `app.singleInstanceEnabled()` |
