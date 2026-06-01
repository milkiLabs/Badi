// User-configurable prefix actions. Loaded from $CONFIG_DIR/config.json.
// Each action has a trigger (typed in the input to switch into prefix mode),
// a display name and icon for the badge, and a shell template that can
// reference the user's query as %s.

const std = @import("std");
const Io = std.Io;
const paths = @import("paths.zig");
const loader = @import("loader.zig");

/// A user-defined prefix action. Triggering is purely textual: when the
/// user types the `trigger` string, the app enters prefix mode with this
/// action bound. Enter runs `action` with %s replaced by the shell-quoted
/// query.
pub const Action = struct {
    trigger: []const u8,
    name: []const u8,
    icon: []const u8,
    action: []const u8,
};

/// Top-level config. Currently only `actions` — kept as a struct so future
/// fields (e.g. `default_mode`, `window`) can be added without changing
/// the loader signature.
pub const Config = struct {
    actions: []const Action = &.{
        .{ .trigger = "g ", .name = "Google", .icon = "🔍", .action = "xdg-open https://google.com/search?q=%s" },
        .{ .trigger = "> ", .name = "Run", .icon = ">", .action = "sh -c %s" },
    },
};

/// Loads config.json from the badi config dir. Same missing-file/parse
/// behavior as `theme.load`.
pub fn load(arena: std.mem.Allocator, env: *const std.process.Environ.Map, io: Io) !Config {
    return loader.loadFromFile(arena, env, io, "config.json", Config{});
}
