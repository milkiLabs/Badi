// XDG .desktop file discovery and parsing.
//
// Scans XDG_DATA_HOME/applications and XDG_DATA_DIRS/applications for
// .desktop files, parses the [Desktop Entry] section, and returns a flat
// list of DesktopEntry (name + exec string). Deduplicates by filename
// across all directories. Filters out hidden, no-display, non-application,
// and desktop-environment-mismatched entries.

const std = @import("std");

const max_desktop_file_size = 1024 * 1024;
const EnvMap = std.process.Environ.Map;

/// A single application ready to display and launch.
pub const DesktopEntry = struct {
    name: []const u8,
    exec: []const u8,

    fn deinit(self: DesktopEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.exec);
    }
};

/// Owned list of desktop entries with its allocator.
pub const DesktopAppList = struct {
    allocator: std.mem.Allocator,
    entries: []DesktopEntry,

    pub fn empty(allocator: std.mem.Allocator) DesktopAppList {
        return .{ .allocator = allocator, .entries = &.{} };
    }

    pub fn deinit(self: *DesktopAppList) void {
        for (self.entries) |entry| entry.deinit(self.allocator);
        self.allocator.free(self.entries);
        self.entries = &.{};
    }
};

/// Intermediate parse result — strings point into the file content, not owned.
const ParsedDesktopEntry = struct {
    name: []const u8,
    exec: []const u8,
    try_exec: []const u8,
};

/// Scans all XDG application directories and returns a deduplicated list.
/// Skips directories that don't exist (not an error — they're optional).
pub fn loadDesktopApps(allocator: std.mem.Allocator, io: std.Io, env: *const EnvMap) !DesktopAppList {
    var apps: std.ArrayList(DesktopEntry) = .empty;
    errdefer deinitEntries(allocator, apps.items);
    defer apps.deinit(allocator);

    // Dedup by filename — same app installed in multiple XDG dirs.
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer deinitSeen(allocator, &seen);
    const locale = currentLocale(env);
    const current_desktops = env.get("XDG_CURRENT_DESKTOP") orelse "";

    // XDG_DATA_HOME takes priority; fall back to ~/.local/share.
    if (env.get("XDG_DATA_HOME")) |xdh| {
        const path = try std.fmt.allocPrint(allocator, "{s}/applications", .{xdh});
        defer allocator.free(path);
        try loadDir(allocator, io, env, &apps, &seen, path, locale, current_desktops);
    } else if (env.get("HOME")) |home| {
        const path = try std.fmt.allocPrint(allocator, "{s}/.local/share/applications", .{home});
        defer allocator.free(path);
        try loadDir(allocator, io, env, &apps, &seen, path, locale, current_desktops);
    }

    // System-wide dirs from XDG_DATA_DIRS.
    const dirs_raw = env.get("XDG_DATA_DIRS") orelse "/usr/local/share:/usr/share";
    var dirs = std.mem.splitScalar(u8, dirs_raw, ':');
    while (dirs.next()) |dir| {
        if (dir.len == 0) continue;
        const path = try std.fmt.allocPrint(allocator, "{s}/applications", .{dir});
        defer allocator.free(path);
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
    while (try iter.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".desktop")) continue;
        if (seen.contains(entry.name)) continue;

        // Track this filename to avoid duplicates across directories.
        const seen_key = try allocator.dupe(u8, entry.name);
        errdefer allocator.free(seen_key);
        try seen.put(allocator, seen_key, {});

        const content = dir.readFileAlloc(io, entry.name, allocator, .limited(max_desktop_file_size)) catch |err| {
            std.log.warn("failed reading desktop file {s}/{s}: {}", .{ dir_path, entry.name, err });
            continue;
        };
        defer allocator.free(content);

        const parsed = parseDesktopFile(content, locale, current_desktops) orelse continue;
        if (!tryExecAvailable(allocator, io, env, parsed.try_exec)) continue;
        const owned_name = try allocator.dupe(u8, parsed.name);
        errdefer allocator.free(owned_name);
        const owned_exec = try allocator.dupe(u8, parsed.exec);
        errdefer allocator.free(owned_exec);
        try apps.append(allocator, .{ .name = owned_name, .exec = owned_exec });
    }
}

fn deinitEntries(allocator: std.mem.Allocator, entries: []DesktopEntry) void {
    for (entries) |entry| entry.deinit(allocator);
}

fn deinitSeen(allocator: std.mem.Allocator, seen: *std.StringHashMapUnmanaged(void)) void {
    var it = seen.keyIterator();
    while (it.next()) |key| allocator.free(key.*);
    seen.deinit(allocator);
}

/// Returns the effective locale from LC_ALL, LC_MESSAGES, or LANG.
fn currentLocale(env: *const EnvMap) []const u8 {
    if (env.get("LC_ALL")) |locale| if (locale.len > 0) return locale;
    if (env.get("LC_MESSAGES")) |locale| if (locale.len > 0) return locale;
    if (env.get("LANG")) |locale| if (locale.len > 0) return locale;
    return "";
}

/// Parses a .desktop file's [Desktop Entry] section.
/// Returns null if the entry should be skipped (hidden, wrong type, etc).
/// All returned strings are slices into `content` — not owned.
pub fn parseDesktopFile(content: []const u8, locale: []const u8, current_desktops: []const u8) ?ParsedDesktopEntry {
    var name: []const u8 = "";
    var localized_name: []const u8 = "";
    var exec: []const u8 = "";
    var try_exec: []const u8 = "";
    var type_value: []const u8 = "";
    var only_show_in: []const u8 = "";
    var not_show_in: []const u8 = "";
    var hidden = false;
    var no_display = false;
    var in_desktop_entry = false;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        if (line[0] == '[') {
            if (in_desktop_entry) break; // past [Desktop Entry], stop
            in_desktop_entry = std.mem.eql(u8, line, "[Desktop Entry]");
            continue;
        }
        if (!in_desktop_entry) continue;

        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const value = std.mem.trim(u8, line[eq + 1 ..], " \t");

        if (std.mem.eql(u8, key, "Type")) {
            type_value = value;
        } else if (std.mem.eql(u8, key, "Hidden")) {
            hidden = parseBoolean(value);
        } else if (std.mem.eql(u8, key, "NoDisplay")) {
            no_display = parseBoolean(value);
        } else if (std.mem.eql(u8, key, "Exec")) {
            exec = value;
        } else if (std.mem.eql(u8, key, "TryExec")) {
            try_exec = value;
        } else if (std.mem.eql(u8, key, "OnlyShowIn")) {
            only_show_in = value;
        } else if (std.mem.eql(u8, key, "NotShowIn")) {
            not_show_in = value;
        } else if (std.mem.eql(u8, key, "Name")) {
            name = value;
        } else if (std.mem.startsWith(u8, key, "Name[") and std.mem.endsWith(u8, key, "]")) {
            // Localized name like Name[fr]=... — first match wins.
            const tag = key[5 .. key.len - 1];
            if (localized_name.len == 0 and localeMatches(tag, locale)) localized_name = value;
        }
    }

    // Filter: must be Type=Application, not hidden, not filtered by desktop env.
    if (hidden or no_display) return null;
    if (!std.mem.eql(u8, type_value, "Application")) return null;
    if (only_show_in.len > 0 and !desktopListMatches(only_show_in, current_desktops)) return null;
    if (not_show_in.len > 0 and desktopListMatches(not_show_in, current_desktops)) return null;
    if (exec.len == 0) return null;

    const display_name = if (localized_name.len > 0) localized_name else name;
    if (display_name.len == 0) return null;
    return .{ .name = display_name, .exec = exec, .try_exec = try_exec };
}

/// Checks if a TryExec binary exists on PATH or as an absolute/relative path.
/// Empty TryExec means "always available" per the XDG spec.
fn tryExecAvailable(allocator: std.mem.Allocator, io: std.Io, env: *const EnvMap, try_exec: []const u8) bool {
    if (try_exec.len == 0) return true;

    // Absolute or relative path with slash — check directly.
    if (std.mem.indexOfScalar(u8, try_exec, '/') != null) {
        std.Io.Dir.cwd().access(io, try_exec, .{ .execute = true }) catch return false;
        return true;
    }

    // Bare filename — search PATH.
    const path_var = env.get("PATH") orelse "/usr/local/bin:/usr/bin:/bin";
    var paths = std.mem.splitScalar(u8, path_var, ':');
    while (paths.next()) |dir| {
        if (dir.len == 0) continue;
        const candidate = std.fs.path.join(allocator, &.{ dir, try_exec }) catch return false;
        defer allocator.free(candidate);
        std.Io.Dir.cwd().access(io, candidate, .{ .execute = true }) catch continue;
        return true;
    }

    return false;
}

fn parseBoolean(value: []const u8) bool {
    return std.ascii.eqlIgnoreCase(value, "true");
}

/// Matches a locale tag (e.g. "fr", "fr_FR") against the user's locale.
/// Normalizes by stripping encoding (.UTF-8) and territory (@desktop).
fn localeMatches(tag: []const u8, locale: []const u8) bool {
    if (locale.len == 0) return false;
    const normalized_len = std.mem.indexOfAny(u8, locale, ".@") orelse locale.len;
    const normalized = locale[0..normalized_len];

    if (std.mem.eql(u8, tag, normalized)) return true;
    const lang_len = std.mem.indexOfScalar(u8, normalized, '_') orelse normalized.len;
    return std.mem.eql(u8, tag, normalized[0..lang_len]);
}

/// Checks if any value in a semicolon-separated list matches any colon-separated desktop.
fn desktopListMatches(semicolon_list: []const u8, current_desktops: []const u8) bool {
    var values = std.mem.splitScalar(u8, semicolon_list, ';');
    while (values.next()) |value| {
        if (value.len == 0) continue;

        var desktops = std.mem.splitScalar(u8, current_desktops, ':');
        while (desktops.next()) |desktop| {
            if (std.mem.eql(u8, value, desktop)) return true;
        }
    }
    return false;
}

test "parseDesktopFile accepts valid application entry" {
    const parsed = parseDesktopFile(
        \\[Desktop Entry]
        \\Type=Application
        \\Name=Terminal
        \\Exec=alacritty --class main
        \\Icon=terminal
    , "en_US.UTF-8", "GNOME").?;

    try std.testing.expectEqualStrings("Terminal", parsed.name);
    try std.testing.expectEqualStrings("alacritty --class main", parsed.exec);
    try std.testing.expectEqualStrings("", parsed.try_exec);
}

test "parseDesktopFile prefers matching localized name" {
    const parsed = parseDesktopFile(
        \\[Desktop Entry]
        \\Type=Application
        \\Name=Settings
        \\Name[fr]=Parametres
        \\Exec=settings
    , "fr_FR.UTF-8", "GNOME").?;

    try std.testing.expectEqualStrings("Parametres", parsed.name);
}

test "parseDesktopFile captures TryExec" {
    const parsed = parseDesktopFile(
        \\[Desktop Entry]
        \\Type=Application
        \\Name=Tool
        \\TryExec=tool-bin
        \\Exec=tool-bin --flag
    , "", "").?;

    try std.testing.expectEqualStrings("tool-bin", parsed.try_exec);
    try std.testing.expectEqualStrings("tool-bin --flag", parsed.exec);
}

test "parseDesktopFile rejects hidden, no-display, and non-application entries" {
    try std.testing.expect(parseDesktopFile(
        \\[Desktop Entry]
        \\Type=Application
        \\Name=Hidden
        \\Exec=hidden
        \\Hidden=true
    , "", "GNOME") == null);

    try std.testing.expect(parseDesktopFile(
        \\[Desktop Entry]
        \\Type=Application
        \\Name=No Display
        \\Exec=no-display
        \\NoDisplay=True
    , "", "GNOME") == null);

    try std.testing.expect(parseDesktopFile(
        \\[Desktop Entry]
        \\Type=Link
        \\Name=Docs
        \\Exec=docs
    , "", "GNOME") == null);
}

test "parseDesktopFile applies desktop environment filters" {
    try std.testing.expect(parseDesktopFile(
        \\[Desktop Entry]
        \\Type=Application
        \\Name=KDE Tool
        \\Exec=kde-tool
        \\OnlyShowIn=KDE;
    , "en_US.UTF-8", "GNOME") == null);

    try std.testing.expect(parseDesktopFile(
        \\[Desktop Entry]
        \\Type=Application
        \\Name=GNOME Tool
        \\Exec=gnome-tool
        \\OnlyShowIn=GNOME;Unity;
    , "en_US.UTF-8", "GNOME:Unity") != null);

    try std.testing.expect(parseDesktopFile(
        \\[Desktop Entry]
        \\Type=Application
        \\Name=Blocked Tool
        \\Exec=blocked-tool
        \\NotShowIn=GNOME;
    , "en_US.UTF-8", "GNOME") == null);
}
