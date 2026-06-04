// Shared helpers for the plugin launch functions. Anything that more
// than one plugin needs (currently `writeStdout` and `launchDetached`)
// lives here so the per-mode handlers in `builtin.zig` stay focused
// on their own dispatch logic.

const std = @import("std");
const qt6 = @import("libqt6zig");
const state = @import("../state/mod.zig");

const stdout_buf_size: usize = 8192;

/// Writes `args` formatted with `fmt` to stdout and flushes. Silently
/// swallows write errors — a launcher's stdout writes rarely surface
/// meaningfully, and a notification toast would be more annoying than
/// useful. Caller is responsible for closing the window.
pub fn writeStdout(app: *state.AppState, comptime fmt: []const u8, args: anytype) void {
    var buf: [stdout_buf_size]u8 = undefined;
    var writer = std.Io.File.stdout().writer(app.io, &buf);
    writer.interface.print(fmt, args) catch {};
    writer.interface.flush() catch {};
}

/// Detached-launches `program` with `args` and records the outcome in
/// `exit_code`. On success, exit_code is 0; on failure (program missing
/// or failed to start), a warning is logged and exit_code is 1. The
/// window is always closed — the user shouldn't be left staring at Badi
/// after a launch attempt either way.
///
/// This is the single place the `StartDetached22` bool return gets
/// honored, so adding a new detached-launch mode is a one-liner that
/// can't accidentally regress to "exit 0 on missing binary".
pub fn launchDetached(app: *state.AppState, program: []const u8, args: []const []const u8) void {
    if (qt6.QProcess.StartDetached22(app.allocator, program, args)) {
        app.exit_code = 0;
    } else {
        std.log.warn("launch failed: {s}", .{program});
        app.exit_code = 1;
    }
    _ = app.ui.main.Close();
}
