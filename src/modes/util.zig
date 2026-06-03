// Shared helpers for the per-mode launch functions. Anything that more
// than one mode needs (currently just `writeStdout`) lives here so the
// per-mode files stay focused on their own dispatch logic.

const std = @import("std");
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
