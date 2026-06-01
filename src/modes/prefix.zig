// Prefix mode: the user typed a configured trigger (e.g. "g ") and then
// typed a query. Run the configured shell template with %s replaced by
// the shell-quoted query. Detached so the launched process survives exit.

const std = @import("std");
const qt6 = @import("libqt6zig");
const state = @import("../state/mod.zig");
const core = @import("../core/mod.zig");

const placeholder_token = "%s";

pub fn launch(app: *state.AppState) void {
    const cfg = app.mode.prefix;
    const text_ptr = app.ui.input.Text(app.allocator);
    defer app.allocator.free(text_ptr);
    const query = text_ptr;
    if (query.len == 0) return;

    const quoted_query = core.exec.quoteShellArg(app.allocator, query) catch return;
    defer app.allocator.free(quoted_query);

    const final_cmd = compose(app.allocator, cfg.action, quoted_query) catch return;
    defer app.allocator.free(final_cmd);

    _ = qt6.QProcess.StartDetached22(app.allocator, "sh", &[_][]const u8{ "-c", final_cmd });
    _ = app.ui.main.Close();
}

/// Substitutes %s in `template` with `quoted_query`. If %s is absent,
/// appends " {quoted_query}" to the template. Both cases produce a string
/// safe for `sh -c` consumption.
fn compose(allocator: std.mem.Allocator, template: []const u8, quoted_query: []const u8) ![]u8 {
    if (std.mem.indexOf(u8, template, placeholder_token)) |idx| {
        return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
            template[0..idx],
            quoted_query,
            template[idx + placeholder_token.len ..],
        });
    }
    return std.fmt.allocPrint(allocator, "{s} {s}", .{ template, quoted_query });
}
