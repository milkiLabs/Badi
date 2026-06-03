// Piped mode: the user has selected a line from stdin. Write it to stdout
// and close with exit code 0. The shell pipe on the other end captures it.

const state = @import("../state/mod.zig");
const util = @import("util.zig");

pub fn launch(app: *state.AppState) void {
    const selection = app.currentSelectionData() orelse return;
    util.writeStdout(app, "{s}\n", .{selection.data});
    app.exit_code = 0;
    _ = app.ui.main.Close();
}
