# Modes Reference

Badi has five modes. Three are **initial modes** (chosen at startup);
two are **mid-session modes** (entered by typing in apps mode).

```zig
pub const AppMode = union(enum) {
    apps: void,                  // initial
    piped: void,                 // initial
    prefix: config.Action,       // mid-session (typed trigger)
    url: void,                   // mid-session (typed URL)
    prompt: PromptConfig,        // initial
};
```

| Mode    | Initial? | Entered by                                                  | Exits to  |
| ------- | -------- | ----------------------------------------------------------- | --------- |
| `apps`  | yes      | `stdin` is not a pipe, no `--prompt`                        | —         |
| `piped` | yes      | `stdin.stat().kind == .named_pipe`                          | —         |
| `prompt`| yes      | `--prompt` flag on the command line                         | —         |
| `prefix`| no       | typing a configured trigger (e.g. `g `) in `apps` mode      | `apps`    |
| `url`   | no       | typing something that `isUrl(text)` recognizes in `apps`    | `apps`    |

## How a mode picks its launch

`Enter` and double-click both call `modes.dispatch(app)`:

```zig
pub fn dispatch(app: *state.AppState) void {
    switch (app.mode) {
        .apps   => @import("apps.zig").launch(app),
        .piped  => @import("piped.zig").launch(app),
        .prefix => @import("prefix.zig").launch(app),
        .url    => @import("url.zig").launch(app),
        .prompt => @import("prompt.zig").launch(app),
    }
}
```

Direct switch (not a function-pointer table) — Zig can't easily coerce
heterogeneous function literals to a single vtable type, and the
inlined switch is the same number of lines.

Each mode's `launch` function is the single point that turns a user
action into a side effect. Adding a new mode = add a variant to
`AppMode`, add a `modes/<name>.zig`, and add the case to the switch
above. Nothing else needs to know.

## Per-mode details

### Apps mode

**Source:** `modes/apps.zig`

Reads the selected `DesktopEntry` from the source list, parses its
`Exec=` string with `core.exec.parseExec`, and launches via
`QProcess.StartDetached22` so the launched app survives Badi's exit.

The "selected" data is resolved by `AppState.currentSelectionData()`,
which dereferences `selected_index` → `visible_indices` → `app_list` to
return the right `exec` string. Pure data — no Qt access.

### Piped mode

**Source:** `modes/piped.zig`

Reads the selected line from `piped_items`, writes `line + "\n"` to
stdout, and closes the window. The shell pipe on the other end captures
the output.

The async stdin pipeline that fills `piped_items` lives in
`ui/callbacks/piped.zig` and is documented in
[piped-mode.md](piped-mode.md).

### Prefix mode

**Source:** `modes/prefix.zig`

Triggered when the user types a configured trigger (e.g. `g `). The
active trigger's `config.Action` is stored in `AppMode.prefix`. The
input field is cleared and shows a badge with the action's icon and
name.

On Enter:
1. Read the query (whatever is in the input after the trigger was
   stripped by `enterPrefixMode`).
2. Shell-quote it via `core.exec.quoteShellArg`.
3. Substitute into the action's template. If the template contains
   `%s`, replace it with the quoted query. If not, append ` quoted`
   to the template.
4. Run via `sh -c "..."` (detached).

### URL mode

**Source:** `modes/url.zig`

Entered when `utils.url.isUrl(text)` returns true (heuristic:
has a scheme, is `localhost[:port]`, or has a `tld` of 2+ letters
with no spaces). The `url` variant replaces the old
`name == "Browser"` string hack from the pre-refactor design.

On Enter:
1. Read the query from the input.
2. If no `http://` or `https://` prefix, prepend `https://`.
3. Run `xdg-open <url>` (detached).

### Prompt mode

**Source:** `modes/prompt.zig`

Entered only via the `--prompt` CLI flag. The input field is the
answer, not a launcher query. The list is hidden and the window
shrinks to 80 px tall.

On Enter: if the input is empty and `!allow_empty`, do nothing
(keep the window open). Otherwise write `text + "\n"` to stdout and
close. On Escape: close with exit code 1.

See [prompt-mode.md](prompt-mode.md) for the full flag reference.

### Emoji mode

**Source:** `modes/emoji.zig`

Entered via the `--emoji` CLI flag (initial) or by typing `": "`
mid-session in apps mode. The list is the full Unicode emoji set
(1914 entries, no skin tone variants) loaded from a pre-packed
binary slab.

On Enter, dispatches to the configured `EmojiAction`:

- `.copy` (default) — `wl-copy` → stdout fallback
- `.print` — write the glyph to stdout, exit 0
- `.type_keys` — `wtype` (falls back to `.copy`)

On Escape: close with exit code 1 (cancelled).

See [emoji-mode.md](emoji-mode.md) for the full flag reference and
data format details.

## How mode transitions happen

### `apps` → `prefix`

In `onTextChanged` (`src/ui/callbacks/text.zig`), iterate
`app.prefixes` and check `matchesTrigger(query, cfg)`. If a trigger
matches, call `helpers.enterPrefixMode` which:

- Sets `app.mode = .{ .prefix = cfg }`
- Sets the badge text to `"{cfg.icon} {cfg.name}"` and shows it
- Clears the input (the trigger is "consumed" by the mode switch)
- Switches the placeholder to `"Type to search or run..."`
- Triggers `view.applyFilter(app, "")` so the synthetic single-row
  list shows the placeholder

### `apps` → `url`

In `onTextChanged`, after the trigger loop, check `url.isUrl(query)`.
If true, call `helpers.enterUrlMode` which:

- Sets `app.mode = .url`
- Sets the badge to `"🌐 Browser"` and shows it
- Switches the placeholder to `"Type a URL..."`

The `url.zig` launch is called directly without further filtering.

### `prefix` / `url` → `apps`

Called in three places:

- `Escape` (in `onKeyPress`): `helpers.exitToApps(app)`
- `Backspace` on empty input: `helpers.exitToApps(app)`
- `Ctrl+W` on empty input: `helpers.exitToApps(app)`

`exitToApps` resets `app.mode = .apps`, hides the badge, restores the
apps placeholder, and re-filters with an empty query.

### `url` → `apps` (on backspace out)

Special case: if the user is in `url` mode and the new text is no
longer a URL, revert to apps mode. This is in `onTextChanged`:

```zig
if (app.mode == .url) {
    if (!url.isUrl(query)) helpers.exitToApps(app);
    view.applyFilter(app, query);
    return;
}
```

### `apps` → `emoji`

Hardcoded trigger (`: `) checked in `onTextChanged` before any
user-configured prefix trigger. Calls `helpers.enterEmojiMode` which:

- Sets `app.mode = .emoji`
- Sets the badge to `"😀 Emoji"` and shows it
- Switches the placeholder to `"Search emojis..."`
- Triggers `view.applyFilter(app, "")` against the emoji entries

`emoji` mode exits to `apps` via the same `exitToApps` path used by
prefix/url: Escape, Backspace on empty input, or Ctrl-W on empty input.

## Adding a new mode

1. Add a variant to `AppMode` in `src/state/mode.zig`. If it needs
   config, add a field to the variant's payload.
2. Add a `src/modes/<name>.zig` file with a `launch(app: *AppState) void`.
3. Add the case to the switch in `src/modes/mod.zig::dispatch`.
4. Add cases to the small switches in:
   - `src/ui/model.zig` — `onModelRowCount` and `onModelData` (what
     the Qt model says for this mode)
   - `src/ui/view.zig` — `fillVisibleIndices`, `computeHasResults`,
     `resultCount` (whether the mode has a list source)
   - `src/ui/status.zig` — `updateNoResults` (what the no-results
     label says; usually `unreachable` if no list source)
5. If the mode is triggered by typing, add a transition helper in
   `src/ui/callbacks/helpers.zig` and a trigger in `onTextChanged`.
6. If the mode is an initial mode, add it to `resolveMode` in
   `src/app/startup.zig`.
7. If the mode needs new CLI flags, add them to `src/app/cli.zig`.

## Source Files

| File                              | Purpose                                              |
| --------------------------------- | ---------------------------------------------------- |
| `src/state/mode.zig`              | `AppMode` union, `PromptConfig`, helpers             |
| `src/modes/mod.zig`               | `dispatch(app)` — single switch                     |
| `src/modes/apps.zig`              | Launch a .desktop entry                              |
| `src/modes/piped.zig`             | Print selected stdin line                            |
| `src/modes/prefix.zig`            | Shell-template substitution + spawn                  |
| `src/modes/url.zig`               | Prepend `https://` if needed + `xdg-open`            |
| `src/modes/prompt.zig`            | Write prompt answer to stdout                        |
| `src/modes/emoji.zig`             | Copy/print/type the selected emoji glyph             |
| `src/core/emoji/`                 | Pre-packed binary slab + loader                      |
| `src/ui/callbacks/text.zig`       | `onTextChanged` — mode transitions + re-filter       |
| `src/ui/callbacks/key.zig`        | `onKeyPress` — Enter, Esc, arrows, Ctrl-W            |
| `src/ui/callbacks/helpers.zig`    | `enterPrefixMode`, `enterUrlMode`, `enterEmojiMode`, `exitToApps` |
| `src/utils/url.zig`               | `isUrl(text)` heuristic                              |
| `src/app/startup.zig`             | `resolveMode` — initial mode (apps / piped / prompt / emoji) |
| `src/app/cli.zig`                 | `--prompt` and `--emoji` flag parsing                |
