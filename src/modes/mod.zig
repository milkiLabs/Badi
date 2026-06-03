// Mode dispatch: the single switch on AppMode that turns a user action
// (Enter, double-click) into the right per-mode launch function. Each
// mode's launch function lives in its own file (`apps.zig`, `piped.zig`,
// etc.) and has the same signature: `fn (app: *AppState) void`.
//
// Adding a new mode = add a variant to `state.AppMode`, add a file here,
// and add its case to the switch below. Nothing else needs to know.

const state = @import("../state/mod.zig");

/// Routes the active mode to its launch function. A direct switch is
/// preferred over a vtable even though every launch function shares the
/// same signature: the compiler enforces exhaustiveness (a new AppMode
/// variant without a dispatch case is a compile error), the inlined
/// direct calls avoid an indirect jump, and the total line count is
/// the same.
pub fn dispatch(app: *state.AppState) void {
    switch (app.mode) {
        .apps => @import("apps.zig").launch(app),
        .piped => @import("piped.zig").launch(app),
        .prefix => @import("prefix.zig").launch(app),
        .url => @import("url.zig").launch(app),
        .prompt => @import("prompt.zig").launch(app),
        .emoji => @import("emoji.zig").launch(app),
    }
}
