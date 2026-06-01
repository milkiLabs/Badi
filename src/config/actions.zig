// User-configurable prefix actions. Loaded from $CONFIG_DIR/config.json.
// Each action has a trigger (typed in the input to switch into prefix mode),
// a display name and icon for the badge, and a shell template that can
// reference the user's query as %s.

const std = @import("std");
const Io = std.Io;
const paths = @import("paths.zig");

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
    return loadFromFile(arena, env, io, "config.json", Config{});
}

fn loadFromFile(arena: std.mem.Allocator, env: *const std.process.Environ.Map, io: Io, filename: []const u8, default: anytype) @TypeOf(default) {
    var dir = paths.resolve(arena, env, io) orelse return default;
    defer dir.close(io);

    const file_content = dir.readFileAlloc(io, filename, arena, .limited(1024 * 1024)) catch {
        writeDefault(dir, io, arena, filename, default);
        return default;
    };

    return std.json.parseFromSliceLeaky(@TypeOf(default), arena, file_content, .{ .ignore_unknown_fields = true }) catch default;
}

fn writeDefault(dir: Io.Dir, io: Io, arena: std.mem.Allocator, filename: []const u8, default: anytype) void {
    const file = dir.createFile(io, filename, .{}) catch return;
    defer file.close(io);

    const json_str = std.json.Stringify.valueAlloc(
        arena,
        default,
        .{ .whitespace = .indent_4 },
    ) catch return;

    file.writePositionalAll(io, json_str, 0) catch {};
}
