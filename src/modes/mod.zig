// Mode dispatch: routes the active mode to its registered plugin's
// `launch` handler. The mode plugin carries its own per-instance state
// via `ActiveMode.ctx`. Adding a new mode = register a new Mode value in
// `plugins/builtin.zig` (or call `plugin.register` from app startup);
// nothing in this file needs to change.

const state = @import("../state/mod.zig");

pub fn dispatch(app: *state.AppState) void {
    app.mode.plugin.launch(app, app.mode.ctx);
}
