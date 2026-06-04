# Plan: Plugin System for Modes (#22) and Actions (#23)

> Status: in flight on branch `plugin`. Trait, registry, and built-in mode
> definitions are committed. The work stops at the dispatch sites that
> still reference the old `AppMode` union enum. This document is the
> recipe for finishing the migration and adding the `config.Action`
> extension.

## Goals

1. **Add a mode without touching the dispatch sites.** Today, every new
   mode touches 7+ files (the union variant, `modes/mod.zig`,
   `ui/model.zig`, `ui/view.zig`, `ui/status.zig`,
   `ui/callbacks/text.zig`, `ui/callbacks/key.zig`,
   `ui/callbacks/helpers.zig`, `app/startup.zig`, `app/exit_code.zig`).
   After this lands, a new mode is *one new file* plus *one registration
   call*.
2. **Let `config.Action` carry more than a shell template.** Users should
   be able to define a prefix that runs an HTTP request, an argv-direct
   exec, or a script — without writing Zig.
3. **Don't regress what the current design got right.** The shell `%s`
   substitution, the per-mode `exit_code` semantics, the per-mode badge,
   the per-mode `no_results` label, the mid-session `exitToApps` rule,
   and the lazy-loaded emoji data should all be expressible through the
   new trait.
4. **Cost we accept:** runtime dispatch (one indirect call per
   launch/filter) and a small per-mode cast where a mode needs
   per-instance state. The roadmap already noted both are paid in
   spirit (the launch calls cross files), so this is bookkeeping rather
   than a real regression.

## Where the branch stands now

Branch `plugin` is one commit on top of `main`
(`66f09a2 "not completed"`). That commit:

| File | State |
|---|---|
| `src/plugins/api.zig` | **NEW** — the `Mode` trait, `ActiveMode`, `Trigger`, `Registry` types; default no-op helpers |
| `src/plugins/builtin.zig` | **NEW** — all 6 built-in modes as `*const api.Mode` values, plus their handler functions; a `modeById` lookup |
| `src/state/app_state.zig` | Half-converted: `mode: AppMode` is now `mode: plugin.ActiveMode`; new `registry`, `registered_modes`, `registered_triggers`, `prompt_context`, `emoji_cli_context`, `emoji_trigger_context` fields; new `hasListSource`, `hasBadge`, `badgeText`, `emptyText`, `canExitToDefault`, `isCancelable`, `singleInstanceEnabled` methods on `AppState` that delegate to the active plugin |
| `src/state/mode.zig` | `AppMode` is now `pub const AppMode = plugin.ActiveMode;`. The `hasListSource` / `hasBadge` methods on the old union are gone — moved to `AppState` |
| `src/modes/mod.zig`, `src/ui/**`, `src/app/**` | **NOT STARTED** — still switch on the old `AppMode` shape. The branch doesn't compile as-is because `AppMode` is no longer a tagged union. |

The trait the branch landed with is **good** — it solves problems my
first plan only partially addressed. We keep it and finish the
migration around it. Below: the trait shape, the design rationale
(including what's better than the first plan), and the migration map.

## The `Mode` trait (kept from the branch)

`src/plugins/api.zig`:

```zig
pub const Context = ?*const anyopaque;

pub const TextResult = enum {
    /// The handler fully handled this keystroke. Caller should not
    /// re-filter.
    handled,
    /// The handler did whatever transition logic it needed; the caller
    /// should run the normal "re-filter in current mode" path.
    continue_filter,
};

pub const SelectionSource = enum {
    none,       // synthetic modes (prefix/url/prompt) — no list to select from
    apps,       // DesktopEntry[]
    piped,      // []const u8 lines
    emoji,      // EmojiEntry[]
};

pub const Mode = struct {
    /// Stable id. Used in logs and `modeById("calc")` lookups.
    id: []const u8,
    name: []const u8,
    /// Default placeholder text for the input field in this mode.
    placeholder: []const u8,
    /// Whether the mode has a real list source. Drives the list
    /// visibility, the no_results label, and whether `filter` is called.
    has_list_source: bool,
    /// Drives `currentSelectionData()` — which slice the selected row
    /// reads from.
    selection_source: SelectionSource = .none,

    /// Optional: returns the badge text. `null` → no badge shown. Used
    /// by the helper that shows/hides the badge widget.
    badgeText: ?*const fn (app: *anyopaque, ctx: Context) ?[]const u8 = null,
    /// Optional: returns the no_results label text. Default "No results".
    emptyText: ?*const fn (app: *const anyopaque, ctx: Context) []const u8 = null,
    /// Number of rows the Qt model exposes. Required.
    resultCount: *const fn (app: *const anyopaque, ctx: Context) usize,
    /// Cell text for `(row, DisplayRole)`. Required.
    displayRow: *const fn (app: *anyopaque, ctx: Context, row: i32) qt6.QVariant,
    /// Fills `app.visible_indices` (and `app.piped_visible_scores` if
    /// needed) for the given query. Required.
    filter: *const fn (app: *anyopaque, ctx: Context, query: []const u8) void,
    /// What to do on Enter / double-click. Required.
    launch: *const fn (app: *anyopaque, ctx: Context) void,

    /// Optional: per-keystroke hook. Default is null = "re-filter".
    /// Modes that need to react to typing (apps, url) override.
    /// Returns `TextResult.handled` if the keystroke was fully consumed
    /// (e.g. mode transition); `continue_filter` if the caller should
    /// also run the re-filter.
    onTextChanged: ?*const fn (
        app: *anyopaque,
        ctx: Context,
        query: []const u8,
    ) TextResult = null,

    /// Optional: called before a mode becomes active. Return `false` to
    /// abort the transition. Used by emoji to lazy-load the data.
    beforeEnter: ?*const fn (app: *anyopaque, ctx: Context) bool = null,

    /// Optional: true if Esc/Backspace-on-empty/Ctrl-W-on-empty exits
    /// to apps (vs closing the window). Default false. Prefix/url/emoji
    /// (when entered via ": ") override.
    canExitToDefault: ?*const fn (app: *const anyopaque, ctx: Context) bool = null,
    /// Optional: true if Esc closes the window with exit code 1.
    /// Default false. Prompt/piped/emoji(--cli) override.
    isCancelable: ?*const fn (app: *const anyopaque, ctx: Context) bool = null,

    /// Opt-in to the single-instance replacement socket. Apps + emoji.
    singleInstance: bool = false,
};
```

The active mode:

```zig
pub const ActiveMode = struct {
    /// Pointer to a static `Mode` value (always one of the registered
    /// ones, never inline).
    plugin: *const Mode,
    /// Optional caller-owned per-instance state. For prefix actions
    /// this points to the `config.Action`; for the prompt mode it
    /// points to the `PromptConfig`; for the emoji mode it points to
    /// the `EmojiConfig` (one of two stored on `AppState`).
    ctx: Context = null,
};
```

Triggers and registry:

```zig
pub const Trigger = struct {
    /// The literal text that activates this mode (e.g. "g ").
    text: []const u8,
    mode: ActiveMode,
};

pub const Registry = struct {
    modes: []const *const Mode,
    triggers: []const Trigger,
};
```

The defaults:

```zig
pub fn defaultResultCount(_: *const anyopaque, _: Context) usize { return 0; }
pub fn emptyDisplayRow(_: *anyopaque, _: Context, _: i32) qt6.QVariant {
    return qt6.QVariant.New();
}
pub fn noFilter(_: *anyopaque, _: Context, _: []const u8) void {}
pub fn noLaunch(_: *anyopaque, _: Context) void {}
```

## Why this design is good (and what the first plan missed)

Things the branch's trait handles better than my first plan:

1. **`TextResult` from `onTextChanged`** — distinguishes "I handled this
   keystroke, don't re-filter" from "I updated mode state, please
   re-filter". My first plan only had a single `onTextChanged` that
   was expected to call `view.applyFilter` itself.
2. **`selection_source: SelectionSource` field** — keeps
   `currentSelectionData` declarative. The first plan would have
   switched on `app.mode.user_data` casts inside `currentSelectionData`,
   which scatters the per-mode structure knowledge.
3. **`singleInstance: bool` field on the mode** — the apps and emoji
   modes opt in. The first plan needed a per-mode list of "which modes
   use single-instance" in `single_instance.zig`.
4. **`beforeEnter: ?fn -> bool`** — emoji uses this to lazy-load its
   data. Cleaner than the current `ensureEmojisLoaded` calls peppered
   in the helpers.
5. **`displayRow` returns `QVariant` directly** — preserves the
   allocator + `QVariant.New24` pattern. My first plan returned
   `[]const u8` and had the model do the QVariant wrapping, which
   changes ownership semantics.
6. **Registry bundles `modes` and `triggers`** — single object passed
   around; no need to look up triggers via id-magic.
7. **Per-instance state stored on `AppState`, not in a `user_data`
   field on `Mode`** — `AppState` already owns it (`prompt_context`,
   `emoji_cli_context`, `emoji_trigger_context`). The `ctx: ?*const
   anyopaque` is the `ActiveMode`'s pointer to that storage. This
   avoids the lifetime problem my first plan had with prefix actions.

Things I would still tweak:

- The branch's `api.zig` imports `qt6` for the `QVariant` return type.
  The trait is no longer pure-Zig. That's a defensible choice (Qt is
  already everywhere the trait is *used*), but it means a unit test for
  the trait needs libqt6zig — which `core_tests.zig` deliberately
  avoids. Document this in the test plan.
- The `displayRow` handlers allocate a string on the heap (e.g.
  `"🚀  rocket"`) just to wrap it in a QVariant. The current
  `emojiRow` in `ui/model.zig` does the same. Acceptable.
- The `urlTextChanged` handler in `builtin.zig` directly mutates
  `app.mode`, `app.ui.badge.Hide()`, and `app.ui.input.SetPlaceholderText`.
  This is a code-smell — the mode plugin reaches into the UI. We'll
  leave it for this PR and consider a `leaveTo` helper in a follow-up.
  (Same as today.)

## What remains to be done (the migration)

Eight files still switch on the old `AppMode` shape and will not
compile against the branch. They are the migration targets.

### 1. `src/modes/mod.zig::dispatch`

Replace the switch with a single call:

```zig
pub fn dispatch(app: *state.AppState) void {
    app.mode.plugin.launch(app, app.mode.ctx);
}
```

The old per-mode `launch` files (`apps.zig`, `piped.zig`, `prefix.zig`,
`url.zig`, `prompt.zig`, `emoji.zig`) become dead code — their
implementation moved to `plugins/builtin.zig`. Delete them, or keep
`util.zig` (still has `writeStdout` and `launchDetached`).

### 2. `src/ui/model.zig::onModelData`

Delete the per-mode switch. Replace with:

```zig
pub fn onModelData(_: qt6.QAbstractListModel, index: qt6.QModelIndex, role: i32) callconv(.c) qt6.QVariant {
    if (role != display_role or !index.IsValid()) return qt6.QVariant.New();
    const app = state.global.assertGet();
    return app.mode.plugin.displayRow(app, app.mode.ctx, index.Row());
}
```

### 3. `src/ui/view.zig::fillVisibleIndices`

Delete the per-mode switch. Replace with a single plugin call:

```zig
fn fillVisibleIndices(app: *state.AppState, query: []const u8) void {
    if (!app.mode.plugin.has_list_source) return;
    app.mode.plugin.filter(app, app.mode.ctx, query);
}
```

The `fillApps`, `fillPiped`, `rankAppsByHistory`, `appHistoryBoost`,
`fillFor` helpers — all gone from `ui/view.zig`. Their equivalents
live in `plugins/builtin.zig` as `appsFilter`, `pipedFilter`,
`emojiFilter`, etc.

### 4. `src/ui/status.zig::updateNoResults`

Replace the mode switch with a plugin call:

```zig
pub fn updateNoResults(app: *state.AppState) void {
    if (!app.mode.plugin.has_list_source) {
        app.ui.no_results.Hide();
        return;
    }
    if (app.visible_indices.items.len > 0) {
        app.ui.no_results.Hide();
        return;
    }
    const callback = app.mode.plugin.emptyText orelse {
        app.ui.no_results.SetText("No results");
        app.ui.no_results.Show();
        return;
    };
    app.ui.no_results.SetText(callback(app, app.mode.ctx));
    app.ui.no_results.Show();
}
```

### 5. `src/ui/callbacks/text.zig::onTextChanged`

Replace the long `if (app.mode == .url) ... if (app.mode == .apps) ...
else ... view.applyFilter` chain with:

```zig
pub fn onTextChanged(_: qt6.QLineEdit, text: [*:0]const u8) callconv(.c) void {
    const app = state.global.assertGet();
    const query: []const u8 = std.mem.span(text);
    if (app.setting_text) return;

    // Per-mode handler — may transition to another mode. Apps handles
    // its own ": " trigger + prefix triggers + URL detection. Url
    // handles the "backspaced out of URL" revert. Other modes get
    // null → "just re-filter".
    if (app.mode.plugin.onTextChanged) |handler| {
        const result = handler(app, app.mode.ctx, query);
        if (result == .continue_filter) view.applyFilter(app, query);
        return;
    }

    // Default: re-filter in the current mode.
    view.applyFilter(app, query);
}
```

The "match a prefix trigger" logic moves into the **apps** mode's
`onTextChanged` handler. New code in `plugins/builtin.zig`:

```zig
fn appsTextChanged(app_opaque: *anyopaque, _: api.Context, query: []const u8) api.TextResult {
    const app = appPtr(app_opaque);
    if (std.mem.eql(u8, query, emoji_trigger)) {
        enterEmojiModeTrigger(app);
        return .handled;
    }
    for (app.registered_triggers.items) |trigger| {
        if (matchesTrigger(query, trigger.text)) {
            enterActionMode(app, trigger.mode);
            return .handled;
        }
    }
    if (url_util.isUrl(query)) {
        enterUrlMode(app);
        return .continue_filter;
    }
    return .continue_filter;
}
```

The emoji trigger detection moves here from the top-level handler.
The url mode's `urlTextChanged` already exists in `builtin.zig` and
needs no further change.

### 6. `src/ui/callbacks/key.zig::canExitToApps` / `isCancelable`

Delete both functions. Replace each call site with:

```zig
// in onKeyPress
if (app.mode.plugin.canExitToDefault) |f| {
    if (f(app, app.mode.ctx)) { helpers.exitToApps(app); }
} else if (app.mode.plugin.isCancelable) |f| {
    if (f(app, app.mode.ctx)) {
        app.exit_code = 1;
        _ = app.ui.main.Close();
    }
} else {
    _ = app.ui.main.Close();
}
```

The two-line `tryExitOnEmpty` for Backspace/Ctrl-W keeps the same
shape — it now reads `canExitToDefault` instead of the deleted
`canExitToApps`.

### 7. `src/ui/callbacks/helpers.zig`

Three new helpers, one trimmed helper:

- `enterEmojiModeTrigger(app)` — sets `app.mode = .{ .plugin = &emoji, .ctx = &app.emoji_trigger_context }`, sets the badge, switches placeholder, runs `view.applyFilter(app, "")`. Calls `app.mode.plugin.beforeEnter` and aborts on false.
- `enterActionMode(app, active_mode)` — sets `app.mode = active_mode`, badge is built via `app.mode.plugin.badgeText`, switches placeholder, runs `view.applyFilter(app, "")`. (Replaces `enterPrefixMode` — the `app.mode` carries the Action via its `ctx`.)
- `enterUrlMode(app)` — sets `app.mode = .{ .plugin = &url, .ctx = null }`, sets the badge, switches placeholder. No filter (the url mode's `onTextChanged` is the one that runs it).
- `exitToApps(app)` — sets `app.mode = .{ .plugin = &apps, .ctx = null }`, hides the badge, switches placeholder to `apps.placeholder`, runs `view.applyFilter(app, "")`.

The "URL mode revert on backspace" path goes through `exitToApps` —
the url mode's `onTextChanged` already does this; it just needs to
call the new `exitToApps` instead of mutating state directly. Worth
refactoring in this PR: move the badge-hide + placeholder + filter
out of `urlTextChanged` and into `exitToApps`.

### 8. `src/app/startup.zig`

- `resolveMode(io, settings)` → `resolveInitialMode(io, settings)`. Each branch becomes a `plugin.modeById("...").?` lookup:

  ```zig
  pub fn resolveInitialMode(
      io: std.Io,
      settings: App.Settings,
      registry: *const plugin.Registry,
  ) state.AppMode {
      _ = registry; // currently unused; reserved for future "user-specified initial mode" config
      if (settings.prompt) |cfg| return .{ .plugin = plugin.modeById("prompt").?, .ctx = @ptrCast(&cfg) };
      if (settings.emoji)  |cfg| return .{ .plugin = plugin.modeById("emoji").?,  .ctx = @ptrCast(&cfg) };
      const stdin = std.Io.File.stdin();
      const stat = stdin.stat(io) catch return .{ .plugin = plugin.modeById("apps").? };
      if (stat.kind == .named_pipe) return .{ .plugin = plugin.modeById("piped").? };
      return .{ .plugin = plugin.modeById("apps").? };
  }
  ```

- `buildState` adds:
  - Static registry assignment: `app_state.registry = .{ .modes = &plugin.builtin.all, .triggers = &.{} }` (the trigger slice is filled in below).
  - Build the dynamic triggers from the loaded config:
    ```zig
    try app_state.registered_triggers.ensureTotalCapacity(gpa, cfg.actions.len);
    for (cfg.actions) |action| {
        try app_state.registered_triggers.append(gpa, .{
            .text = action.trigger,
            .mode = .{ .plugin = &plugin.builtin.action, .ctx = @ptrCast(&action) },
        });
    }
    ```
  - `app_state.prompt_context = settings.prompt orelse .{};` (with a sentinel default; only used when prompt is the initial mode).
  - `app_state.emoji_cli_context = settings.emoji orelse .{ .entry = .cli };`
  - `app_state.emoji_trigger_context = .{ .entry = .trigger };`
  - Use the right ctx when resolving the initial mode: for the prompt mode, `ctx = &app_state.prompt_context`; for emoji (initial), `ctx = &app_state.emoji_cli_context`.

- `prepareInitialFrame` switches on the active mode plugin to decide
  the first paint. Today it checks `app.mode == .piped` to install the
  stdin notifier and to skip the filter. New shape:

  ```zig
  pub fn prepareInitialFrame(app: *state.AppState, arena: std.mem.Allocator, settings: App.Settings) void {
      // stdin notifier for piped mode
      if (std.mem.eql(u8, app.mode.plugin.id, "piped")) {
          const stdin = std.Io.File.stdin();
          const notifier = qt6.QSocketNotifier.New4(stdin.handle, ..., app.ui.main);
          notifier.OnActivated(ui.callbacks.onStdinActivated);
      }
      ui.factory.configureInitialFrame(app.ui, arena, settings);

      // First paint
      if (std.mem.eql(u8, app.mode.plugin.id, "emoji")) {
          if (app.mode.plugin.beforeEnter) |f| _ = f(app, app.mode.ctx);
          ui.view.applyFilter(app, "");
      } else if (std.mem.eql(u8, app.mode.plugin.id, "apps")) {
          ui.view.applyFilter(app, "");
      } else if (std.mem.eql(u8, app.mode.plugin.id, "piped")) {
          ui.status.updateNoResults(app);
      } else {
          // prefix/url/prompt — nothing to do for first paint
      }
  }
  ```

  The `id`-string comparison is acceptable here because the initial
  mode is one of a small fixed set; if it grows, this becomes a
  `plugin.modeById` lookup of a small enum.

### 9. `src/app/exit_code.zig::resolve`

```zig
pub fn resolve(app: *state.AppState) u8 {
    const code: u8 = app.exit_code orelse defaultExitCode(app.mode.plugin);
    if (code == 0) recordSuccessfulAppLaunch(app);
    return code;
}

fn defaultExitCode(mode: *const plugin.Mode) u8 {
    // Could become a `default_exit_code: u8` field on the trait; for
    // now, encode as id lookup to keep the trait size unchanged.
    if (std.mem.eql(u8, mode.id, "piped")) return 1;
    if (std.mem.eql(u8, mode.id, "prompt")) return 1;
    if (std.mem.eql(u8, mode.id, "emoji")) return 1;
    return 0;
}
```

Consider adding `default_exit_code: u8 = 0` to the `Mode` struct as a
follow-up. For this PR, the id-switch keeps the trait shape stable.

### 10. `src/app/cli.zig`

No changes needed — `--prompt` and `--emoji` parsing stays the same.
The settings get passed to `resolveInitialMode` and into
`prompt_context` / `emoji_cli_context` on `AppState`.

### 11. `src/app/single_instance.zig`

`enabled(mode)` currently does `mode == .apps or mode == .emoji`. New
shape: `app.singleInstanceEnabled()`. Single call site.

### 12. `src/app/mod.zig::App.create`

The `app_state` is built with `mode: undefined` (placeholder), then
`resolveInitialMode` fills it. Today `buildState` calls
`resolveMode` inline; same pattern after — `buildState` calls
`resolveInitialMode`. Also, `App.create` no longer needs to import
`plugin` directly; `AppState.registry` is populated by `buildState`.

### 13. Dead code removal

After the migration, these files are unused and should be deleted:

- `src/modes/apps.zig`
- `src/modes/piped.zig`
- `src/modes/prefix.zig`
- `src/modes/url.zig`
- `src/modes/prompt.zig`
- `src/modes/emoji.zig`
- `src/modes/mod.zig` (replaced by `plugins/builtin.zig` + `plugins/api.zig`'s default no-op `noLaunch`)

`src/modes/util.zig` stays — its `writeStdout` and `launchDetached`
are still used by the plugin handlers.

The old `AppMode` union's `hasListSource` / `hasBadge` methods are
already gone from the branch (moved to `AppState` as plugin delegates).
Confirm no other call sites reference them.

### 14. `src/core_tests.zig`

The pure-core test runner needs to know about the new modules.
`plugins/api.zig` is pure Zig *except* for the `qt6.QVariant` return
type of `displayRow`. Two options:

1. **Test the trait structure only** (id lookup, registry iteration,
   trigger matching) by constructing fake `Mode` instances with
   `defaultResultCount` + `emptyDisplayRow` + `noFilter` + `noLaunch`.
   This avoids the `qt6` import in the test path.
2. **Skip plugin tests in `core_tests`** and add them to a new
   `plugins_tests.zig` that does pull in `libqt6zig`. Run under
   `zig build test` (the existing `run_exe_tests` step already does
   this).

I lean toward option 2 — `plugins/api.zig` is in the same boat as
`ui/` and `modes/` (the comment in `core_tests.zig` already says these
need a Qt-initialized test binary). Add a `plugins_tests.zig` and
include it in `core_tests.zig` only if we keep it Qt-free; otherwise
let it be exercised by the existing `run_exe_tests` step.

## #23 — Action kind field

### Schema extension (`src/config/actions.zig`)

The branch did NOT touch `config.Action`. We add the `kind` field on
top of what's there.

```zig
pub const Kind = enum {
    /// Default. `action` is a shell template; `%s` is replaced with the
    /// shell-quoted query and run via `sh -c "..."` (detached). Today's
    /// behavior; backward-compatible because `kind` is omitted from the
    /// default JSON.
    shell,

    /// `program` is run with `args`, with `%s` replaced in each. No
    /// shell. Same detached-launch semantics.
    argv,

    /// `url` is fetched via `curl`. `method` defaults to "GET". `%s` is
    /// replaced with a URL-encoded query in the URL. The response body
    /// goes to stdout; the process exits 0.
    http,

    /// `script` is the path to a script; the query is passed as `$1`.
    /// No shell. Same detached-launch semantics.
    script,
};

pub const Action = struct {
    trigger: []const u8,
    name: []const u8,
    icon: []const u8,
    kind: Kind = .shell,        // <-- new; default .shell

    // .shell
    action: ?[]const u8 = null,        // existing field

    // .argv
    program: ?[]const u8 = null,
    args: ?[]const []const u8 = null,

    // .http
    url: ?[]const u8 = null,
    method: ?[]const u8 = null,

    // .script
    script: ?[]const u8 = null,
};
```

The loader doesn't change: `std.json.parseFromSliceLeaky` with
`ignore_unknown_fields = true` already handles optional fields;
`kind` is optional and defaults to `.shell`. The default `Config{}`
writes `"kind": "shell"` on first run so users see the field in the
example.

Add a small post-parse validator in `config/actions.zig::load` that
warns (`std.log.warn`) when a kind is set but its required field is
missing. Piggyback on roadmap #10.

### Dispatch (`src/plugins/builtin.zig::actionLaunch`)

`actionLaunch` switches on `action.kind`:

```zig
fn actionLaunch(app_opaque: *anyopaque, ctx: api.Context) void {
    const app = appPtr(app_opaque);
    const cfg = actionPtr(ctx);
    const text_ptr = app.ui.input.Text(app.allocator);
    defer app.allocator.free(text_ptr);
    if (text_ptr.len == 0) return;

    switch (cfg.kind) {
        .shell  => launchShell(app, cfg.action.?, text_ptr),
        .argv   => launchArgv(app, cfg.program.?, cfg.args.?, text_ptr),
        .http   => launchHttp(app, cfg.url.?, cfg.method orelse "GET", text_ptr),
        .script => launchScript(app, cfg.script.?, text_ptr),
    }
}
```

Four helpers (in `builtin.zig`, or a new
`plugins/action_kinds.zig` if the file grows too long):

- `launchShell(app, template, query)` — today's `compose` + `sh -c` + `launchDetached`. Unchanged.
- `launchArgv(app, program, args, query)` — substitute `%s` in each arg, `QProcess.StartDetached22(app, program, args)`. No shell. If `args` is null, pass only the program.
- `launchHttp(app, url, method, query)` — substitute `%s` (URL-encoded) in `url`; run `curl -sS -X METHOD "$final_url"` detached. Reuses `core.exec.quoteShellArg` (since the URL still goes through a shell). On success, the response body appears on stdout (curl writes to stdout by default). On `curl` missing, log a warning + exit 1.
- `launchScript(app, script, query)` — `QProcess.StartDetached22(app, script, &.{query})`. POSIX `$1` convention.

### Test config

```json
{
  "actions": [
    {"trigger": "g ",   "name": "Google",     "icon": "🔍", "kind": "shell",  "action": "xdg-open https://google.com/search?q=%s"},
    {"trigger": "> ",   "name": "Run",        "icon": ">",  "kind": "shell",  "action": "sh -c %s"},
    {"trigger": "ip ",  "name": "IP lookup",  "icon": "🌐", "kind": "http",   "url": "https://ipinfo.io/%s/json"},
    {"trigger": "fb ",  "name": "Find file",  "icon": "🔎", "kind": "script", "script": "/home/me/bin/find-file"},
    {"trigger": "git ", "name": "git",        "icon": "🌱", "kind": "argv",   "program": "git", "args": ["%s"]}
  ]
}
```

## Files to touch (final tally)

### Branch `plugin` has these (don't re-do)

- `src/plugins/api.zig`
- `src/plugins/builtin.zig`
- `src/state/app_state.zig` (partial — see migration #9 above for the `exit_code` part)
- `src/state/mode.zig`

### Migration targets (this PR)

- `src/modes/mod.zig` — replace switch with plugin call
- `src/modes/{apps,piped,prefix,url,prompt,emoji}.zig` — **delete**
- `src/ui/model.zig` — replace switch with plugin call
- `src/ui/view.zig` — replace switch + drop the `fillApps`/`fillPiped`/`fillFor` helpers
- `src/ui/status.zig` — replace switch with plugin call
- `src/ui/callbacks/text.zig` — collapse if/else chain to plugin call
- `src/ui/callbacks/key.zig` — replace `canExitToApps`/`isCancelable` switches
- `src/ui/callbacks/helpers.zig` — add `enterEmojiModeTrigger`, `enterActionMode`; trim `enterUrlMode` to delegate to `exitToApps`'s revert path
- `src/app/startup.zig` — `resolveMode` → `resolveInitialMode`; populate `registry` and `registered_triggers`; build `prompt_context`/`emoji_*_context`
- `src/app/exit_code.zig` — replace switch with id-based default
- `src/app/single_instance.zig` — `enabled(mode)` → `app.singleInstanceEnabled()`
- `src/app/mod.zig` — wire up the new state fields if needed
- `src/core_tests.zig` — include the new modules (or add `plugins_tests.zig`)

### Action schema (#23)

- `src/config/actions.zig` — add `Kind` enum, new fields, default JSON entry
- `src/plugins/builtin.zig` — extend `actionLaunch` with the four kinds
- (optional) `src/plugins/action_kinds.zig` — split the four helpers out

### Docs

- `docs/modes.md` — update "Adding a new mode" recipe to the 2-file version; add a "Plugin API" section documenting the trait
- `docs/roadmap.md` — move #22 and #23 to a "Done" section (or remove)
- `docs/user-docs/actions.md` — document the four kinds with one example each
- `notes/plan.md` — add a one-liner that the dispatch is now runtime vtable
- `notes/plan-plugin-system.md` (this file)

## Implementation order (single PR, but commit-by-commit compilable)

1. **`src/modes/mod.zig::dispatch`** — first because it's the smallest change and proves the plugin system compiles. After this, `zig build` should succeed (the other ui/app sites still switch on the *old* `AppMode` shape; if they don't, fix the `state/mode.zig` to keep `AppMode` as the old union for one more commit).
2. **`src/ui/model.zig`, `src/ui/view.zig`, `src/ui/status.zig`** — three small switches, all become single vtable calls. After this, the list display, filter, and no-results work for every mode via the plugin.
3. **`src/ui/callbacks/key.zig`** — drop the two helper switches. After this, Esc/Backspace/Ctrl-W work via `canExitToDefault` / `isCancelable`.
4. **`src/ui/callbacks/text.zig`** — collapse the if/else chain. Move the ": " trigger + URL detection + prefix matching into `appsTextChanged` in `builtin.zig`. After this, mode transitions work via `onTextChanged`.
5. **`src/ui/callbacks/helpers.zig`** — new `enterEmojiModeTrigger`, `enterActionMode`, refactored `enterUrlMode` + `exitToApps`.
6. **`src/app/startup.zig::resolveInitialMode`** — switch the initial-mode resolution to plugin lookups; populate `registry` and `registered_triggers`. After this, the app boots into the right mode.
7. **`src/app/exit_code.zig::resolve`** — replace the switch with id-based default.
8. **`src/app/single_instance.zig::enabled`** — single replacement.
9. **Delete the old per-mode files** in `src/modes/`. Remove `src/modes/mod.zig` (the new dispatch is a one-liner that can live in `src/main.zig` or be a function on `AppState`).
10. **`src/state/mode.zig`** — at this point, `AppMode` is fully the plugin type. Confirm the re-export still works for all the call sites that reference it.
11. **Action schema extension (`#23`)** — add `Kind` enum, fields, defaults. Update `builtin.zig::actionLaunch` to dispatch. Add a `curl` availability check + fallback for the `http` kind.
12. **Tests** — add `plugins_tests.zig` (or extend `core_tests.zig` if kept pure). Cover: id lookup, registry iteration, trigger matching, kind dispatch.
13. **Docs** — `docs/modes.md` recipe, `docs/roadmap.md` move, `docs/user-docs/actions.md` kinds, `notes/plan.md` one-liner.

## Test plan

- **Compile** — `zig build` succeeds at every step of the commit sequence. The current branch does not compile; step 1 of the order above makes it compile.
- **Pure-Zig** — `core_tests.zig` adds coverage for `plugins/api.zig` if the trait stays Qt-free. If the trait keeps `qt6.QVariant` (current branch), coverage goes in `plugins_tests.zig` (new) and is run via the existing `run_exe_tests` step.
- **Manual smoke** for each mode (one keystroke each):
  - `apps` — open an app via Enter.
  - `piped` — `echo a | badi`, press Enter, see `a\n` on stdout.
  - `prefix` (g ) — see Google badge, type, Enter, browser opens.
  - `url` — type `example.com`, see Browser badge, Enter, browser opens.
  - `prompt` — `badi --prompt Name`, type, Enter, see stdout.
  - `emoji` (`--emoji` and `: ` trigger) — see badge, search, Enter, clipboard set.
- **Action kinds** — one config entry per kind; trigger each; verify the right process runs.
- **Single-instance** — start `badi`, then `badi` again; verify the first instance closes (apps + emoji modes; piped/prompt/prefix/url do not opt in).
- **Backward compat** — config file with no `kind` field still parses as `.shell` and launches correctly.

## Open questions (decide before code)

1. **Where do the four `launch*` helpers for the action kinds live?** Inside `plugins/builtin.zig` (keeps related code together, but the file is already 480 lines) or in a new `plugins/action_kinds.zig` (cleaner split)? I lean `action_kinds.zig` so `builtin.zig` stays focused on the mode handlers.

2. **HTTP kind: scope.** Start with just `method` + URL-substitution, or also `headers` and `body`? I'd start with method + URL — same shape as `shell` (one template, one substitution), and leave headers/body for a follow-up. The `?` in roadmap Q3 makes this a single addition.

3. **`argv` kind: how strict about arg count?** If `args` is null or empty, run the program with no args. If an `args[i]` is empty after `%s` substitution, pass it as `""` or skip it? Default to passing `""` so positional meaning is preserved. Document this.

4. **Default exit code on the trait.** Add `default_exit_code: u8 = 0` to the `Mode` struct now, or keep the id-based switch in `exit_code.zig` for this PR and add the field as a follow-up? I lean keep-the-switch-for-now — it's 4 lines, the trait is settled, and the field is an obvious small follow-up.

5. **Per-mode `onTextChanged` default.** The trait has `onTextChanged: ?fn = null`. The default in `text.zig` is "re-filter". Modes with handlers return `continue_filter` (caller also re-filters) or `handled` (caller does not). The `apps` and `url` modes have handlers; the others (piped, prefix, emoji, prompt) get the default. Confirm this matches your mental model.

6. **Plugin trait tests.** Keep `plugins/api.zig` importing `qt6` (it has to, for `QVariant`)? Or extract a pure-Zig core trait and a thin Qt-aware extension? The current branch has the qt6 import and the tests live in `plugins_tests.zig` (run under the Qt-aware test step). I'd keep it that way — the existing comment in `core_tests.zig` already says "modes/, ui/ need Qt-initialized test binary", and plugins/ joins that list. The trait is small enough that the import is contained.
