// Prompt mode (--prompt): the input field is the answer. On Enter, write
// the typed text to stdout and exit with code 0. Empty input is rejected
// unless --allow-empty was passed (matches `read` semantics).

const std = @import("std");
const state = @import("../state/mod.zig");

const stdout_buf_size: usize = 8192;

pub fn launch(app: *state.AppState) void {
    const cfg = app.mode.prompt;
    const text_ptr = app.ui.input.Text(app.allocator);
    defer app.allocator.free(text_ptr);
    const answer = text_ptr;

    if (answer.len == 0 and !cfg.allow_empty) return;

    const stdout = std.Io.File.stdout();
    var buf: [stdout_buf_size]u8 = undefined;
    var writer = stdout.writer(app.io, &buf);
    writer.interface.print("{s}\n", .{answer}) catch {};
    writer.interface.flush() catch {};
    app.exit_code = 0;
    _ = app.ui.main.Close();
}
