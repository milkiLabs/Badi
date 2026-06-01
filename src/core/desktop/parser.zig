// .desktop file parser. Reads the [Desktop Entry] section, applies
// visibility filters (Type=Application, Hidden, NoDisplay, OnlyShowIn,
// NotShowIn), and resolves localized names.
// The returned ParsedDesktopEntry holds slices into the input content.

const std = @import("std");

/// Intermediate parse result. Strings are slices into the file content;
/// the caller is responsible for duplicating the ones it wants to keep.
pub const ParsedDesktopEntry = struct {
    name: []const u8,
    exec: []const u8,
    try_exec: []const u8,
};

/// Parses a .desktop file's [Desktop Entry] section. Returns null if the
/// entry should be skipped (hidden, wrong type, filtered by desktop env).
pub fn parse(content: []const u8, locale: []const u8, current_desktops: []const u8) ?ParsedDesktopEntry {
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
    if (only_show_in.len > 0 and !listMatches(only_show_in, current_desktops)) return null;
    if (not_show_in.len > 0 and listMatches(not_show_in, current_desktops)) return null;
    if (exec.len == 0) return null;

    const display_name = if (localized_name.len > 0) localized_name else name;
    if (display_name.len == 0) return null;
    return .{ .name = display_name, .exec = exec, .try_exec = try_exec };
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

/// Checks if any value in a semicolon-separated list matches any colon-
/// separated desktop in XDG_CURRENT_DESKTOP.
fn listMatches(semicolon_list: []const u8, current_desktops: []const u8) bool {
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

/// Returns the effective locale from LC_ALL, LC_MESSAGES, or LANG.
pub fn resolveLocale(env: *const std.process.Environ.Map) []const u8 {
    if (env.get("LC_ALL")) |locale| if (locale.len > 0) return locale;
    if (env.get("LC_MESSAGES")) |locale| if (locale.len > 0) return locale;
    if (env.get("LANG")) |locale| if (locale.len > 0) return locale;
    return "";
}

test "parse accepts valid application entry" {
    const parsed = parse(
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

test "parse prefers matching localized name" {
    const parsed = parse(
        \\[Desktop Entry]
        \\Type=Application
        \\Name=Settings
        \\Name[fr]=Parametres
        \\Exec=settings
    , "fr_FR.UTF-8", "GNOME").?;

    try std.testing.expectEqualStrings("Parametres", parsed.name);
}

test "parse captures TryExec" {
    const parsed = parse(
        \\[Desktop Entry]
        \\Type=Application
        \\Name=Tool
        \\TryExec=tool-bin
        \\Exec=tool-bin --flag
    , "", "").?;

    try std.testing.expectEqualStrings("tool-bin", parsed.try_exec);
    try std.testing.expectEqualStrings("tool-bin --flag", parsed.exec);
}

test "parse rejects hidden, no-display, and non-application entries" {
    try std.testing.expect(parse(
        \\[Desktop Entry]
        \\Type=Application
        \\Name=Hidden
        \\Exec=hidden
        \\Hidden=true
    , "", "GNOME") == null);

    try std.testing.expect(parse(
        \\[Desktop Entry]
        \\Type=Application
        \\Name=No Display
        \\Exec=no-display
        \\NoDisplay=True
    , "", "GNOME") == null);

    try std.testing.expect(parse(
        \\[Desktop Entry]
        \\Type=Link
        \\Name=Docs
        \\Exec=docs
    , "", "GNOME") == null);
}

test "parse applies desktop environment filters" {
    try std.testing.expect(parse(
        \\[Desktop Entry]
        \\Type=Application
        \\Name=KDE Tool
        \\Exec=kde-tool
        \\OnlyShowIn=KDE;
    , "en_US.UTF-8", "GNOME") == null);

    try std.testing.expect(parse(
        \\[Desktop Entry]
        \\Type=Application
        \\Name=GNOME Tool
        \\Exec=gnome-tool
        \\OnlyShowIn=GNOME;Unity;
    , "en_US.UTF-8", "GNOME:Unity") != null);

    try std.testing.expect(parse(
        \\[Desktop Entry]
        \\Type=Application
        \\Name=Blocked Tool
        \\Exec=blocked-tool
        \\NotShowIn=GNOME;
    , "en_US.UTF-8", "GNOME") == null);
}
