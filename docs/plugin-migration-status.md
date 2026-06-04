# Plugin System Migration: Remaining Work

> Status snapshot of branch `plugin-migration` after the mode
> migration. Read alongside [plan-plugin-system.md](plan-plugin-system.md)
> (the master plan) and `git log --oneline main..HEAD`.

## Done (10 commits)

1. `src/modes/mod.zig::dispatch` — single vtable call.
2. `src/ui/{model,view,status}.zig` — per-mode switches replaced
   with single vtable calls.
3. `src/ui/callbacks/{text,key}.zig` — collapsed to vtable calls;
   `appsTextChanged` owns the trigger loop.
4. `src/ui/callbacks/helpers.zig` — thin re-export of
   `plugins/builtin.zig` transition wrappers.
5. `src/app/startup.zig::resolveInitialMode` — plugin lookups;
   `registered_triggers` populated.
6. `src/app/exit_code.zig::resolve` — id-based default lookup.
7. `src/app/single_instance.zig::enabled` — `app.singleInstanceEnabled()`.
8. `src/modes/` — deleted (per-mode files and `mod.zig`); `util.zig`
   moved to `plugins/util.zig`.
9. `src/state/mode.zig` — `AppMode = plugin.ActiveMode` re-export.
10. Docs — `docs/modes.md`, `docs/roadmap.md`,
    `docs/user-docs/actions.md`, `docs/plan-plugin-system.md`.

`zig build` and `zig build test` pass.

## Bug fix post-migration

After the initial 10 commits, two latent bugs surfaced when run on
the real binary:

- `--emoji` (initial mode): `cfg.action` read as `0xfe` (corrupt
  enum tag), panicking at `switch (cfg.action)` in
  `emojiLaunch`.
- `--prompt` (initial mode): `ctx.?` panicked with "attempt to use
  null value" in `promptPtr`.

Root cause: `App.create` returned `App` by value, and `App.state`
was a value-typed `state.AppState`. The `buildState` function took
`&app_state.emoji_cli_context` against a *local* on `App.create`'s
stack frame, and that pointer dangles the moment the struct is
moved into the returned `App`. The prompt case was worse: the ctx
was never set, so it was just `null`.

A third latent bug had the same shape: `buildState::registered_triggers`
took `&owned` against a loop-local variable, which dangles when the
loop iteration ends.

The fix was to **heap-allocate the AppState** in `buildState` so the
address is stable for the whole process. The signature is now
`buildState(...) !*AppState` and `App.state: *AppState`. No more
two-phase init, no more "fixup after move" dance.

`App.destroy` adds `self.gpa.destroy(self.state)` after `deinit`.

## Cleanup pass

After the heap-alloc refactor, a small cleanup pass removed dead
code that was never read:

- `AppState.registry: plugin.Registry` field — set in `buildState`
  but never read. The `plugin.Registry` type itself was unused
  outside the dead field; removed.
- `AppState.registered_modes: std.ArrayList(*const plugin.Mode)` —
  vestigial dynamic counterpart of the static `Registry`. Never
  populated or read. Removed.
- `AppState.hasBadge()` method — duplicate of `badgeText() != null`
  and never called. Removed.
- `view.zig::applyFilter` early return for "prompt" — the prompt
  mode's `has_list_source = false` already prevents the filter
  call, so the id check was dead. Removed.
- `EmojiAction` import in `app_state.zig` — only used by the
  removed `hasBadge`. Removed.

## Remaining (3 items)

### 1. #23 — `config.Action.Kind` extension

**File:** `src/config/actions.zig`

Add the `Kind` enum and per-kind fields:

```zig
pub const Kind = enum { shell, argv, http, script };

pub const Action = struct {
    trigger: []const u8,
    name: []const u8,
    icon: []const u8,
    kind: Kind = .shell,

    // .shell
    action: ?[]const u8 = null,
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

The `std.json.parseFromSliceLeaky` loader already handles optional
fields with `ignore_unknown_fields = true`, so the `kind` field
defaults to `.shell` for existing config files (backward-compatible).

**File:** `src/plugins/builtin.zig::actionLaunch`

Switch on `cfg.kind` and call one of four helpers:

- `launchShell(app, template, query)` — current behavior
  (compose + `sh -c` + `launchDetached`).
- `launchArgv(app, program, args, query)` — `%s` substitution in
  each arg, `QProcess.StartDetached22(app, program, args)`. No
  shell. Empty arg after substitution → pass `""` (preserve
  positional meaning).
- `launchHttp(app, url, method, query)` — `%s` URL-encoded, run
  `curl -sS -X METHOD "$final_url"` detached. Response body on
  stdout. `curl` missing → log warn + exit 1.
- `launchScript(app, script, query)` — `QProcess.StartDetached22(app,
  script, &.{query})`. POSIX `$1` convention. No shell.

**File:** `src/app/startup.zig` — when duplicating `cfg.actions` into
`app_state.prefixes`, dup the new `kind`-dependent fields too:

```zig
const owned: config.Action = .{
    .trigger = try gpa.dupe(u8, action.trigger),
    .name = try gpa.dupe(u8, action.name),
    .icon = try gpa.dupe(u8, action.icon),
    .kind = action.kind,
    .action = if (action.action) |a| try gpa.dupe(u8, a) else null,
    .program = if (action.program) |p| try gpa.dupe(u8, p) else null,
    .args = if (action.args) |a| blk: {
        const out = try gpa.alloc([]const u8, a.len);
        for (a, 0..) |arg, i| out[i] = try gpa.dupe(u8, arg);
        break :blk out;
    } else null,
    .url = if (action.url) |u| try gpa.dupe(u8, u) else null,
    .method = if (action.method) |m| try gpa.dupe(u8, m) else null,
    .script = if (action.script) |s| try gpa.dupe(u8, s) else null,
};
```

Also add a `validate` post-parse step in `config/actions.zig::load`
that warns on "kind set but required field missing" (e.g.
`kind: argv` with no `program`). This piggybacks on roadmap #10.

**Decisions pending**: See plan-plugin-system.md "Open questions" §1
(where do the four helpers live — `plugins/builtin.zig` or
`plugins/action_kinds.zig`?) and §2 (HTTP scope — start with
method + URL, defer headers/body).

### 2. Tests

`src/plugins/api.zig` imports `qt6` (for the `QVariant` return type
of `displayRow`). This puts the plugin tests in the same boat as
`ui/` and the old `modes/` — they need a Qt-initialized test
binary.

**Option A** (recommended): add `src/plugins_tests.zig` and include
it via the existing `addTest` step in `build.zig` (the `run_exe_tests`
step already pulls in `exe.root_module` and links Qt).

**Option B**: add a `refAllDecls` line to `src/core_tests.zig`. This
won't work — `core_tests.zig` deliberately avoids Qt, and the
plugin tests need Qt for the `QVariant` calls.

**Coverage targets**:

- `modeById` lookup (positive + negative).
- `all` slice iteration order is stable.
- `transitions.matchesTrigger(query, prefix)` — exact match.
- `transitions.enterMode` — sets `app.mode`, updates badge,
  switches placeholder, runs `beforeEnter`, aborts on `false`.
- `app_state.registered_triggers` is built from the loaded config
  in the right order.
- After #23: `actionLaunch` dispatches to the right `launch*` for
  each `Kind`. (Hard to test in isolation without a Qt widget tree
  to read the input from — may need a small `mockAppState` helper
  that injects a fake input text.)

### 3. Docs polish

Mostly done. The remaining gaps:

- `docs/cicd.md` — if there's a CI test step, add `plugins_tests.zig`
  to the run. (Need to check the file before adding.)
- `docs/architecture.md` — the data-flow diagram still says "switch
  on `AppMode`" in the dispatch node. Update to "vtable call on
  `app.mode.plugin`". (Need to read the file first.)
- After #23 lands: add a one-paragraph "Plugin system" section to
  the README if there isn't one already. (Low priority — the
  user-facing doc is `user-docs/actions.md`.)

## Migration commit log (newest first)

```
378fbdf docs: update modes/roadmap/plan for the plugin system migration
cf849a1 delete dead per-mode files; move util to plugins/
2bff804 migrate mode dispatch from union switch to plugin vtable
9ba62b6 (cherry-picked) plugin system: add Mode trait, registry, and built-in modes
```

(The plan file's first commit is `626949a` — the plan itself, on
`plugin-migration`. The `9ba62b6` cherry-pick is the original
"not completed" commit from the `plugin` branch.)
