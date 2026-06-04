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
    const code: u8 = app.exit_code orelse defaultExitCode(app.mode.plugin);
    if (code == 0) recordSuccessfulAppLaunch(app);
    return code;
}

/// Per-mode default exit code. The set of "cancelled" modes
/// (piped/prompt/emoji) gets 1; everything else gets 0. Encoded by id
/// so we don't have to add a `default_exit_code: u8` field to the
/// plugin trait for this PR.
fn defaultExitCode(mode: *const @import("../plugins/api.zig").Mode) u8 {
    const id = mode.id;
    if (std.mem.eql(u8, id, "piped")) return 1;
    if (std.mem.eql(u8, id, "prompt")) return 1;
    if (std.mem.eql(u8, id, "emoji")) return 1;
    return 0;
}

fn recordSuccessfulAppLaunch(app: *state.AppState) void {
    const app_id = app.launched_app_id orelse return;
    core.launch_history.recordLaunch(&app.launch_history, app.env, app.io, app_id) catch |err| {
        std.log.warn("failed recording launch history for {s}: {}", .{ app_id, err });
    };
    app.launched_app_id = null;
}
