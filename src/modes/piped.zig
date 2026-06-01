// Piped mode: the user has selected a line from stdin. Write it to stdout
// and close with exit code 0. The shell pipe on the other end captures it.

const std = @import("std");
const state = @import("../state/mod.zig");

const stdout_buf_size: usize = 8192;

pub fn launch(app: *state.AppState) void {
    const selection = app.currentSelectionData() orelse return;
    writeLineAndExit(app, selection.data, 0);
}

fn writeLineAndExit(app: *state.AppState, line: []const u8, exit_code: u8) void {
    const stdout = std.Io.File.stdout();
    var buf: [stdout_buf_size]u8 = undefined;
    var writer = stdout.writer(app.io, &buf);
    writer.interface.print("{s}\n", .{line}) catch {};
    writer.interface.flush() catch {};
    app.exit_code = exit_code;
    _ = app.ui.main.Close();
}
