// Theme type and loader. Theme is loaded from $CONFIG_DIR/theme.json; on
// first run (file missing) the defaults are written to disk so the user
// can find and edit them.

const std = @import("std");
const Io = std.Io;
const paths = @import("paths.zig");

/// User-configurable visual theme. All fields have defaults — unknown JSON
/// fields are ignored. Slices are borrowed from the loader's arena and live
/// for the duration of the loader's arena.
pub const Theme = struct {
    background_color: []const u8 = "#1e1e2e",
    text_color: []const u8 = "#cdd6f4",
    accent_color: []const u8 = "#89b4fa",
    input_background: []const u8 = "#313244",
    border_color: []const u8 = "#45475a",
    hover_color: []const u8 = "#45475a",
    placeholder_color: []const u8 = "#6c7086",
    selected_text_color: []const u8 = "#1e1e2e",
    font_family: []const u8 = "sans-serif",
    font_size: u32 = 15,
    font_weight: []const u8 = "normal",
    window_width: u32 = 600,
    window_height: u32 = 450,
    window_padding: u32 = 14,
    item_spacing: u32 = 6,
    border_radius: u32 = 6,
    border_width: u32 = 1,
    input_padding: u32 = 10,
    item_padding: u32 = 10,
};

/// Loads theme.json from the badi config dir. On missing-file, writes the
/// defaults to disk so the user can find them, and returns the defaults.
/// On parse error, also returns the defaults
pub fn load(arena: std.mem.Allocator, env: *const std.process.Environ.Map, io: Io) !Theme {
    return loadFromFile(arena, env, io, "theme.json", Theme{});
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
