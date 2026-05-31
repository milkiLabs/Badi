const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;

/// A user-configurable action/prefix.
pub const Action = struct {
    trigger: []const u8,
    name: []const u8,
    icon: []const u8,
    action: []const u8,
};

/// Top-level config loaded from ~/.config/badi/config.json.
pub const Config = struct {
    actions: []const Action = &.{
        .{ .trigger = "g ", .name = "Google", .icon = "🔍", .action = "xdg-open https://google.com/search?q=%s" },
        .{ .trigger = "> ", .name = "Run", .icon = ">", .action = "sh -c %s" },
    },
};

/// User-configurable theme. Loaded from ~/.config/badi/theme.json.
/// All fields have defaults — unknown JSON fields are ignored.
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

/// Reads theme.json from the config dir. On first run (file missing),
/// writes defaults to disk so the user can find and edit them.
pub fn loadTheme(arena: std.mem.Allocator, env_map: *const std.process.Environ.Map, io: Io) !Theme {
    return loadJson(arena, env_map, io, "theme.json", Theme{});
}

/// Reads config.json from the config dir. On first run (file missing),
/// writes defaults to disk so the user can find and edit them.
pub fn loadConfig(arena: std.mem.Allocator, env_map: *const std.process.Environ.Map, io: Io) !Config {
    return loadJson(arena, env_map, io, "config.json", Config{});
}

/// Generic JSON config loader: reads a file from the config dir, parses it,
/// and writes defaults if missing.
fn loadJson(arena: std.mem.Allocator, env_map: *const std.process.Environ.Map, io: Io, filename: []const u8, default: anytype) @TypeOf(default) {
    var dir = openConfigDir(arena, env_map, io) orelse return default;
    defer dir.close(io);

    const file_content = dir.readFileAlloc(io, filename, arena, .limited(1024 * 1024)) catch {
        writeDefaultJson(dir, io, arena, filename, default);
        return default;
    };

    return std.json.parseFromSliceLeaky(@TypeOf(default), arena, file_content, .{ .ignore_unknown_fields = true }) catch default;
}

/// Returns ~/.config/badi/ (or $XDG_CONFIG_HOME/badi/), creating it if needed.
fn openConfigDir(arena: std.mem.Allocator, env_map: *const std.process.Environ.Map, io: Io) ?Dir {
    const home = env_map.get("HOME") orelse return null;
    const xdg_config_home = env_map.get("XDG_CONFIG_HOME");

    const config_dir_path = if (xdg_config_home) |xdg|
        std.fs.path.join(arena, &.{ xdg, "badi" }) catch return null
    else
        std.fs.path.join(arena, &.{ home, ".config", "badi" }) catch return null;

    return Dir.cwd().createDirPathOpen(io, config_dir_path, .{}) catch null;
}

/// Serializes a default config value to disk as pretty-printed JSON.
fn writeDefaultJson(dir: Dir, io: Io, arena: std.mem.Allocator, filename: []const u8, default: anytype) void {
    const file = dir.createFile(io, filename, .{}) catch return;
    defer file.close(io);

    const json_str = std.json.Stringify.valueAlloc(
        arena,
        default,
        .{ .whitespace = .indent_4 },
    ) catch return;

    file.writePositionalAll(io, json_str, 0) catch {};
}

/// Builds a Qt Style Sheet (QSS) string from the theme.
/// Double braces `{{`/`}}` are literal braces — std.fmt uses single `{`/}` for interpolation.
pub fn generateQss(allocator: std.mem.Allocator, t: Theme) ![]const u8 {
    const qss =
        \\QWidget {{
        \\    background-color: {s};
        \\    color: {s};
        \\    font-family: '{s}';
        \\    font-size: {d}px;
        \\    font-weight: {s};
        \\}}
        \\QLineEdit {{
        \\    background-color: {s};
        \\    border: {d}px solid {s};
        \\    padding: {d}px;
        \\    border-radius: {d}px;
        \\    color: {s};
        \\}}
        \\QLineEdit::placeholder {{
        \\    color: {s};
        \\}}
        \\QListWidget {{
        \\    background-color: transparent;
        \\    border: none;
        \\    outline: none;
        \\}}
        \\QListWidget::item {{
        \\    padding: {d}px;
        \\    border-radius: {d}px;
        \\}}
        \\QListWidget::item:selected {{
        \\    background-color: {s};
        \\    color: {s};
        \\}}
        \\QListWidget::item:hover {{
        \\    background-color: {s};
        \\}}
    ;

    return std.fmt.allocPrint(allocator, qss, .{
        t.background_color,
        t.text_color,
        t.font_family,
        t.font_size,
        t.font_weight,
        t.input_background,
        t.border_width,
        t.border_color,
        t.input_padding,
        t.border_radius,
        t.text_color,
        t.placeholder_color,
        t.item_padding,
        t.border_radius,
        t.accent_color,
        t.selected_text_color,
        t.hover_color,
    });
}
