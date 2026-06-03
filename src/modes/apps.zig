// Apps mode: the user has selected a .desktop file. Parse its Exec string
// into argv and launch via QProcess (detached so it survives Badi exit).

const std = @import("std");
const state = @import("../state/mod.zig");
const core = @import("../core/mod.zig");
const util = @import("util.zig");

pub fn launch(app: *state.AppState) void {
    const selection = app.currentSelectionData() orelse return;
    var command = core.exec.parseExec(app.allocator, selection.data) catch |err| {
        std.log.warn("failed parsing desktop Exec command '{s}': {}", .{ selection.data, err });
        return;
    };
    defer command.deinit();
    util.launchDetached(app, command.program(), command.args());
}
