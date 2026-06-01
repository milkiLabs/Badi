// Stdin pipeline. The QSocketNotifier fires when data is available on
// stdin; this callback reads in 64 KB chunks, splits on newlines, and
// hands each complete line to `piped_view.appendPipedItem`. The notifier
// is disabled on EOF or persistent read errors.

const std = @import("std");
const qt6 = @import("libqt6zig");
const state = @import("../../state/mod.zig");
const status = @import("../status.zig");
const piped_view = @import("../piped_view.zig");

const stdin_buf_size: usize = 64 * 1024;
const newline: u8 = '\n';
const cr: u8 = '\r';

/// Reads from stdin in non-blocking chunks and dispatches complete lines.
pub fn onStdinActivated(notifier: qt6.QSocketNotifier, _: qt6.QSocketDescriptor, _: i32) callconv(.c) void {
    var buf: [stdin_buf_size]u8 = undefined;
    const n = std.posix.read(std.posix.STDIN_FILENO, &buf) catch |err| switch (err) {
        error.WouldBlock => return,
        else => {
            std.log.warn("failed reading stdin: {}", .{err});
            notifier.SetEnabled(false);
            return;
        },
    };

    const app = state.global.get();

    if (n == 0) {
        // EOF: flush the trailing partial line (no newline) and stop watching.
        flushTrailingLine(app) catch {};
        notifier.SetEnabled(false);
        app.stdin_eof = true;
        status.updateNoResults(app);
        return;
    }

    appendBytes(app, buf[0..n]) catch |err| {
        std.log.warn("failed buffering stdin: {}", .{err});
        notifier.SetEnabled(false);
    };
}

fn appendBytes(app: *state.AppState, bytes: []const u8) !void {
    try app.stdin_pending.appendSlice(app.allocator, bytes);

    // Batch repaints: one BeginResetModel/EndResetModel for the whole chunk.
    app.ui.list.SetUpdatesEnabled(false);
    defer app.ui.list.SetUpdatesEnabled(true);

    var start: usize = 0;
    while (std.mem.indexOfScalarPos(u8, app.stdin_pending.items, start, newline)) |nl| {
        try appendLine(app, app.stdin_pending.items[start..nl]);
        start = nl + 1;
    }
    piped_view.renderPipedAppendBatch(app);

    if (start > 0) {
        try app.stdin_pending.replaceRange(app.allocator, 0, start, &.{});
    }
}

fn flushTrailingLine(app: *state.AppState) !void {
    if (app.stdin_pending.items.len == 0) return;
    try appendLine(app, app.stdin_pending.items);
    app.stdin_pending.clearRetainingCapacity();
    piped_view.renderPipedAppendBatch(app);
}

fn appendLine(app: *state.AppState, raw_line: []const u8) !void {
    const trimmed = std.mem.trimEnd(u8, raw_line, &.{cr});
    if (trimmed.len == 0) return;
    const owned = try app.allocator.dupe(u8, trimmed);
    try piped_view.appendPipedItem(app, owned);
}
