const std = @import("std");
const Io = std.Io;
const paths = @import("paths.zig");

pub fn loadFromFile(arena: std.mem.Allocator, env: *const std.process.Environ.Map, io: Io, filename: []const u8, default: anytype) @TypeOf(default) {
    var dir = paths.resolve(arena, env, io) orelse return default;
    defer dir.close(io);

    const file_content = dir.readFileAlloc(io, filename, arena, .limited(1024 * 1024)) catch {
        writeDefault(dir, io, arena, filename, default);
        return default;
    };

    return std.json.parseFromSliceLeaky(@TypeOf(default), arena, file_content, .{ .ignore_unknown_fields = true }) catch default;
}

pub fn writeDefault(dir: Io.Dir, io: Io, arena: std.mem.Allocator, filename: []const u8, default: anytype) void {
    const file = dir.createFile(io, filename, .{}) catch return;
    defer file.close(io);

    const json_str = std.json.Stringify.valueAlloc(
        arena,
        default,
        .{ .whitespace = .indent_4 },
    ) catch return;

    file.writePositionalAll(io, json_str, 0) catch {};
}
