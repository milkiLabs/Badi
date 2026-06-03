// Prompt mode (--prompt): the input field is the answer. On Enter, write
// the typed text to stdout and exit with code 0. Empty input is rejected
// unless --allow-empty was passed (matches `read` semantics).

const state = @import("../state/mod.zig");
const util = @import("util.zig");

pub fn launch(app: *state.AppState) void {
    const cfg = app.mode.prompt;
    const text_ptr = app.ui.input.Text(app.allocator);
    defer app.allocator.free(text_ptr);
    const answer = text_ptr;

    if (answer.len == 0 and !cfg.allow_empty) return;

    util.writeStdout(app, "{s}\n", .{answer});
    app.exit_code = 0;
    _ = app.ui.main.Close();
}
