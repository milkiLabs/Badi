// Desktop app loader. Orchestrates the XDG dir scan, file parsing,
// and dedup. Composes the lower-level pieces: xdg, parser, entry.

const std = @import("std");
const EnvMap = std.process.Environ.Map;
const entry = @import("entry.zig");
const parser = @import("parser.zig");
const xdg = @import("xdg.zig");

const max_desktop_file_size: usize = 1024 * 1024;

pub const DesktopEntry = entry.DesktopEntry;
pub const DesktopAppList = entry.DesktopAppList;

/// Scans all XDG application directories and returns a deduplicated list.
/// Skips directories that don't exist (not an error — they're optional).
/// Filters out hidden, no-display, non-application, desktop-mismatched,
/// and TryExec-unavailable entries.
pub fn load(allocator: std.mem.Allocator, io: std.Io, env: *const EnvMap) !DesktopAppList {
    var apps: std.ArrayList(DesktopEntry) = .empty;
    errdefer deinitEntries(allocator, apps.items);
    defer apps.deinit(allocator);

    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer deinitSeen(allocator, &seen);

    const locale = parser.resolveLocale(env);
    const current_desktops = env.get("XDG_CURRENT_DESKTOP") orelse "";

    var dirs: std.ArrayList([]const u8) = .empty;
    defer {
        for (dirs.items) |p| allocator.free(p);
        dirs.deinit(allocator);
    }
    try xdg.dataDirs(allocator, env, &dirs);

    for (dirs.items) |path| {
        try loadDir(allocator, io, env, &apps, &seen, path, locale, current_desktops);
    }

    return .{
        .allocator = allocator,
        .entries = try apps.toOwnedSlice(allocator),
    };
}

/// Loads all .desktop files from a single directory into the apps list.
fn loadDir(
    allocator: std.mem.Allocator,
    io: std.Io,
    env: *const EnvMap,
    apps: *std.ArrayList(DesktopEntry),
    seen: *std.StringHashMapUnmanaged(void),
    dir_path: []const u8,
    locale: []const u8,
    current_desktops: []const u8,
) !void {
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir, error.AccessDenied => {
            std.log.debug("skipping desktop app dir {s}: {}", .{ dir_path, err });
            return;
        },
        else => return err,
    };
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |e| {
        if (e.kind != .file) continue;
        if (!std.mem.endsWith(u8, e.name, ".desktop")) continue;
        if (seen.contains(e.name)) continue;

        // Track this filename to avoid duplicates across directories.
        const seen_key = try allocator.dupe(u8, e.name);
        errdefer allocator.free(seen_key);
        try seen.put(allocator, seen_key, {});

        const content = dir.readFileAlloc(io, e.name, allocator, .limited(max_desktop_file_size)) catch |err| {
            std.log.warn("failed reading desktop file {s}/{s}: {}", .{ dir_path, e.name, err });
            continue;
        };
        defer allocator.free(content);

        const parsed = parser.parse(content, locale, current_desktops) orelse continue;
        if (!xdg.tryExecAvailable(allocator, io, env, parsed.try_exec)) continue;
        const owned_name = try allocator.dupe(u8, parsed.name);
        errdefer allocator.free(owned_name);
        const owned_exec = try allocator.dupe(u8, parsed.exec);
        errdefer allocator.free(owned_exec);
        try apps.append(allocator, .{ .name = owned_name, .exec = owned_exec });
    }
}

fn deinitEntries(allocator: std.mem.Allocator, entries: []DesktopEntry) void {
    for (entries) |entry_| entry_.deinit(allocator);
}

fn deinitSeen(allocator: std.mem.Allocator, seen: *std.StringHashMapUnmanaged(void)) void {
    var it = seen.keyIterator();
    while (it.next()) |key| allocator.free(key.*);
    seen.deinit(allocator);
}
