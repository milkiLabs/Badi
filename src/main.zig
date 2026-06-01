// Entry point. Parses CLI, builds the App, runs the event loop.

const std = @import("std");
const app = @import("app/mod.zig");

pub fn main(init: std.process.Init) !u8 {
    const settings = try app.cli.parse(init.arena.allocator(), init.minimal.args);
    var instance = app.App.create(init, settings) catch |err| switch (err) {
        error.AlreadyRunning => return 0,
        else => return err,
    };
    defer instance.destroy();
    return instance.run();
}
