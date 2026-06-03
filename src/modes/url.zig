// URL mode: the user typed something that looks like a URL. Open it with
// xdg-open. Prepends https:// if no scheme is present. Detached so the
// launched browser/process survives Badi exit.

const std = @import("std");
const state = @import("../state/mod.zig");
const util = @import("util.zig");

const https_prefix = "https://";

pub fn launch(app: *state.AppState) void {
    const text_ptr = app.ui.input.Text(app.allocator);
    defer app.allocator.free(text_ptr);
    const query = text_ptr;
    if (query.len == 0) return;

    const target = blk: {
        if (hasScheme(query)) break :blk query;
        const buf = app.allocator.alloc(u8, https_prefix.len + query.len) catch return;
        @memcpy(buf[0..https_prefix.len], https_prefix);
        @memcpy(buf[https_prefix.len..], query);
        break :blk buf;
    };
    defer if (!hasScheme(query)) app.allocator.free(target);

    util.launchDetached(app, "xdg-open", &.{target});
}

fn hasScheme(text: []const u8) bool {
    return std.mem.startsWith(u8, text, "http://") or std.mem.startsWith(u8, text, "https://");
}
