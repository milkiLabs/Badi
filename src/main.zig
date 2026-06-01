// Entry point. Parses CLI, builds the App, runs the event loop.

const std = @import("std");
const app = @import("app/mod.zig");

pub fn main(init: std.process.Init) !u8 {
    const settings = try app.cli.parse(init.arena.allocator(), init.minimal.args);
    var instance = try app.App.create(init, settings);
    defer instance.destroy();
    return instance.run();
}
