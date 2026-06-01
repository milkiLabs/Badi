# App Lifecycle

`App` is the composition root — the one place that knows about every
module. It has three methods:

```zig
const App = @import("app/mod.zig").App;

var instance = try App.create(init, settings);
defer instance.destroy();
return instance.run();
```

## `App.create(init, settings) !App`

**Where:** `src/app/mod.zig:32`

Builds everything but does **not** start the event loop. Returns an
`App` by value. The returned `App` is uninitialized for the event loop —
call `run` for that.

Steps:

1. Initialize Qt (`qt6.init` → `QApplication.New`).
2. Load the theme via `config.loadTheme`. If the theme file is missing,
   the defaults are written to disk and returned.
3. Build the widget tree via `ui.factory.build(arena, theme, settings.prompt)`.
   The prompt-mode chrome (smaller window, hidden list, password echo) is
   applied here if `--prompt` was passed.
4. Apply the QSS theme via `ui.factory.applyTheme`.
5. Wire the C-ABI signals via `ui.factory.wireSignals(widgets, .{
   on_text_changed, on_key_press, on_model_row_count, on_model_data,
   on_item_double_clicked, on_stdin_activated })`. The stdin's
   `on_stdin_activated` is wired even if not currently used — it's a
   null pointer that the notifier activation would only call if it existed.
6. Load the AppState via `startup.buildState`. This:
   - Loads user-configured prefix actions from `config.loadActions`,
     duplicating the slices into the long-lived gpa (the loader's arena
     is freed after duping).
   - Loads `.desktop` apps synchronously into `app_state.app_list`
     (skipped in prompt mode).

Returns the assembled `App` (by value). The AppState lives inside the
returned App.

**Important:** `state.global` is **not** set in `create`. The AppState is
a local `app_state` that gets moved into `self.state` when `create`
returns. Setting the global here would leave a dangling pointer. `run`
sets it once `self` is in its final stack frame.

Error handling: each step is paired with an `errdefer` that unwinds the
already-initialized bits. If `create` fails, the caller never sees a
partially-initialized `App`.

## `App.run(self: *App) u8`

**Where:** `src/app/mod.zig:80`

Resolves the actual mode, prepares the first frame, shows the window,
runs the event loop, and returns the process exit code. **Synchronous** —
does not return until the user closes the window or triggers an exit.

Steps:

1. `state.global.set(&self.state)` — install the C-ABI global pointer.
   Has to happen here, not in `create`, because the AppState is moved
   into `self` when `create` returns. Setting it in `create` would leave
   a dangling pointer.
2. `startup.resolveMode` — see [architecture.md](architecture.md#overview).
   Returns the initial `AppMode` (`.apps`, `.piped`, or `.prompt`).
3. `startup.prepareInitialFrame` — for piped mode, install the
   `QSocketNotifier`; for prompt mode, set the title, prefill, and
   focus; for apps mode, do the first filter pass. See
   [architecture.md](architecture.md) for per-mode details.
4. `ui.main.Show()` — show the window. Qt invokes `onModelRowCount` /
   `onModelData` to populate the list during the first layout pass.
5. `qt6.QApplication.Exec()` — block until the event loop exits.
6. `app.exit_code.resolve(&self.state)` — pick the final exit code.

The returned `u8` is what `main` returns to the OS.

## `App.destroy(self: *App) void`

**Where:** `src/app/mod.zig:95`

Releases resources in **reverse order of allocation**:

1. `self.state.deinit()` — frees `app_list`, `piped_items`,
   `stdin_pending`, `prefixes` (with their inner slices), `current_query`,
   `visible_indices`. **Not** the widget handles — Qt owns them.
2. `self.qapp.Delete()` — frees all Qt-owned widgets (main, list, input,
   badge, model, no_results) and the notifier (parented to main).
3. `qt6.deinit(self.gpa, self.argv)` — frees the `argv` buffer that
   `qt6.init` allocated.

The caller is responsible for calling `destroy` after a successful
`create`. The `main.zig` shim does this with `defer`.

## Error handling

Each step in `create` has a matching `errdefer` that unwinds the
already-initialized bits. If any step fails, the function returns an
error and no App is exposed to the caller — there's nothing to clean up.

`run` and `destroy` are infallible (modulo panics from Qt).
