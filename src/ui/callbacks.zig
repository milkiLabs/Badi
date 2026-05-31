const std = @import("std");
const qt6 = @import("libqt6zig");
const qk = qt6.qnamespace_enums.Key;
const context = @import("../context.zig");
const window = @import("window.zig");
const launcher = @import("../core/launcher.zig");

/// Exits prefix mode back to apps mode.
fn exitPrefixMode(app: *context.AppState) void {
    app.mode = .apps;
    app.list_dirty = true;
    app.ui.badge.Hide();
    app.ui.input.SetPlaceholderText("Search apps...");
    window.resetToMainList();
}

fn isUrl(text: []const u8) bool {
    if (std.mem.startsWith(u8, text, "http://")) return true;
    if (std.mem.startsWith(u8, text, "https://")) return true;
    
    if (std.mem.indexOfScalar(u8, text, ' ') != null) return false;
    
    if (std.mem.startsWith(u8, text, "localhost:")) return true;
    if (std.mem.eql(u8, text, "localhost")) return true;

    const last_dot = std.mem.lastIndexOfScalar(u8, text, '.') orelse return false;
    if (last_dot == 0 or last_dot == text.len - 1) return false;
    
    const tld = text[last_dot + 1 ..];
    if (tld.len < 2 or tld.len > 10) return false;
    for (tld) |c| {
        if (!std.ascii.isAlphabetic(c)) return false;
    }
    
    if (std.mem.startsWith(u8, text, "www.")) return true;

    const common_tlds = [_][]const u8{
        "com", "org", "net", "io", "co", "dev", "app", "me", "ly", "xyz", "edu", "gov", "tv", "ai"
    };
    for (common_tlds) |t| {
        if (std.ascii.eqlIgnoreCase(tld, t)) return true;
    }
    
    return false;
}

/// Triggered whenever the user types in the QLineEdit.
pub fn onTextChanged(_: qt6.QLineEdit, text: [*:0]const u8) callconv(.c) void {
    const app = context.state();
    const query: []const u8 = text[0..std.mem.len(text)];

    // If we're in the dynamic URL prefix mode and the user backspaces the scheme/url, revert to apps mode.
    if (app.mode == .prefix) {
        if (std.mem.eql(u8, app.mode.prefix.name, "Browser")) {
            if (!isUrl(query)) {
                exitPrefixMode(app);
            }
        }
    }

    // If we are in apps mode, check if the user typed a prefix trigger
    if (app.mode == .apps) {
        for (app.prefixes.items) |cfg| {
            if (query.len >= cfg.trigger.len and std.mem.eql(u8, query[0..cfg.trigger.len], cfg.trigger)) {
                app.mode = .{ .prefix = cfg };
                app.list_dirty = true;
                const badge_text = std.fmt.allocPrint(app.allocator, "{s} {s}", .{ cfg.icon, cfg.name }) catch return;
                defer app.allocator.free(badge_text);
                app.ui.badge.SetText(badge_text);
                app.ui.badge.Show();
                app.ui.input.SetText("");
                app.ui.input.SetPlaceholderText("Type to search or run...");
                return;
            }
        }

        if (isUrl(query)) {
            const has_scheme = std.mem.startsWith(u8, query, "http://") or std.mem.startsWith(u8, query, "https://");
            app.mode = .{ .prefix = .{
                .trigger = "",
                .name = "Browser",
                .icon = "🌐",
                .action = if (has_scheme) "xdg-open %s" else "xdg-open https://%s",
            } };
            app.list_dirty = true;
            app.ui.badge.SetText("🌐 Browser");
            app.ui.badge.Show();
            window.filterList(query);
            return;
        }
    }

    // In prefix mode with empty input — just show nothing, stay in prefix mode
    // (Exit prefix mode is handled by Backspace key in onKeyPress)
    window.filterList(query);
}

/// Triggered when the user double clicks an application in the QListWidget.
pub fn onItemDoubleClicked(_: qt6.QListWidget, _: qt6.QListWidgetItem) callconv(.c) void {
    launcher.executeSelection();
}

pub fn onStdinActivated(notifier: qt6.QSocketNotifier, _: qt6.QSocketDescriptor, _: i32) callconv(.c) void {
    var buf: [64 * 1024]u8 = undefined;
    const n = std.posix.read(std.posix.STDIN_FILENO, &buf) catch |err| switch (err) {
        error.WouldBlock => return,
        else => {
            std.log.warn("failed reading stdin: {}", .{err});
            notifier.SetEnabled(false);
            return;
        },
    };

    if (n == 0) {
        flushPendingStdinLine() catch {};
        notifier.SetEnabled(false);
        const app = context.state();
        if (app.piped_items.items.len == 0) {
            app.ui.no_results.SetText("No input");
            app.ui.no_results.Show();
        }
        return;
    }

    appendStdinBytes(buf[0..n]) catch |err| {
        std.log.warn("failed buffering stdin: {}", .{err});
        notifier.SetEnabled(false);
    };
}

fn appendStdinBytes(bytes: []const u8) !void {
    const app = context.state();
    try app.stdin_pending.appendSlice(app.allocator, bytes);

    app.ui.list.SetUpdatesEnabled(false);
    defer app.ui.list.SetUpdatesEnabled(true);

    var start: usize = 0;
    while (std.mem.indexOfScalarPos(u8, app.stdin_pending.items, start, '\n')) |newline| {
        try appendStdinLine(app.stdin_pending.items[start..newline]);
        start = newline + 1;
    }

    if (start > 0) {
        try app.stdin_pending.replaceRange(app.allocator, 0, start, &.{});
    }
}

fn flushPendingStdinLine() !void {
    const app = context.state();
    if (app.stdin_pending.items.len == 0) return;
    try appendStdinLine(app.stdin_pending.items);
    app.stdin_pending.clearRetainingCapacity();
}

fn appendStdinLine(raw_line: []const u8) !void {
    const app = context.state();
    const trimmed = std.mem.trimEnd(u8, raw_line, "\r");
    if (trimmed.len == 0) return;
    try window.appendPipedItem(try app.allocator.dupe(u8, trimmed));
}

/// Key event interceptor for QLineEdit to map Up/Down/Enter over to the QListWidget/Launcher.
pub fn onKeyPress(self: qt6.QLineEdit, event: qt6.QKeyEvent) callconv(.c) void {
    const app = context.state();
    const key = event.Key();

    if (key == qk.Key_Escape) {
        if (app.mode == .prefix) {
            exitPrefixMode(app);
            event.Accept();
            return;
        }
        _ = app.ui.main.Close();
        event.Accept();
    } else if (key == qk.Key_Return or key == qk.Key_Enter) {
        launcher.executeSelection();
        event.Accept();
    } else if (key == qk.Key_Up) {
        window.selectRelative(-1);
        event.Accept();
    } else if (key == qk.Key_Down) {
        window.selectRelative(1);
        event.Accept();
    } else if (key == qk.Key_Backspace) {
        if (app.mode == .prefix) {
            const current_text = self.Text(app.allocator);
            defer app.allocator.free(current_text);
            if (current_text.len == 0) {
                exitPrefixMode(app);
                event.Accept();
                return;
            }
        }
        self.SuperKeyPressEvent(event);
    } else {
        self.SuperKeyPressEvent(event);
    }
}
