// Exit code resolution. After the Qt event loop exits, this is the single
// place that decides the process exit code based on the final AppState.

const std = @import("std");
const core = @import("../core/mod.zig");
const state = @import("../state/mod.zig");

/// Returns the process exit code. If the user selected something, the
/// mode's launch function set `exit_code` to 0. Otherwise, we fall back
/// to a sensible default per mode: piped/prompt/emoji without a selection
/// → 1 (cancelled); apps/prefix/url without a selection → 0 (window
/// closed normally). Emoji is grouped with piped/prompt because the user
/// explicitly invoked a sub-mode — closing without picking is a cancel.
pub fn resolve(app: *state.AppState) u8 {
    const code: u8 = app.exit_code orelse switch (app.mode) {
        .piped, .prompt, .emoji => 1,
        .apps, .prefix, .url => 0,
    };
    if (code == 0) recordSuccessfulAppLaunch(app);
    return code;
}

fn recordSuccessfulAppLaunch(app: *state.AppState) void {
    const app_id = app.launched_app_id orelse return;
    core.launch_history.recordLaunch(&app.launch_history, app.env, app.io, app_id) catch |err| {
        std.log.warn("failed recording launch history for {s}: {}", .{ app_id, err });
    };
    app.launched_app_id = null;
}
