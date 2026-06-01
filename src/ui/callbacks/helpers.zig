// Shared helpers for the callback modules. Things that more than one
// callback needs (mode transitions, badge management) live here so the
// callbacks stay focused on signal handling.

const std = @import("std");
const state = @import("../../state/mod.zig");
const config = @import("../../config/mod.zig");
const view = @import("../view.zig");

const placeholder_apps = "Search apps...";
const placeholder_prefix = "Type to search or run...";
const placeholder_url = "Type a URL...";
const browser_icon = "🌐";
const browser_name = "Browser";

/// Resets the app to apps mode: hide the badge, restore the apps
/// placeholder, re-filter with an empty query. Used when leaving prefix
/// or URL mode (backspace to empty input, Escape, Ctrl-W on empty input).
pub fn exitToApps(app: *state.AppState) void {
    app.mode = .apps;
    app.ui.badge.Hide();
    app.ui.input.SetPlaceholderText(placeholder_apps);
    view.applyFilter(app, "");
}

/// Enters prefix mode: switch the mode, show the badge with the action's
/// icon and name, clear the input, switch placeholder.
pub fn enterPrefixMode(app: *state.AppState, cfg: config.Action) void {
    app.mode = .{ .prefix = cfg };
    const text = std.fmt.allocPrint(app.allocator, "{s} {s}", .{ cfg.icon, cfg.name }) catch return;
    defer app.allocator.free(text);
    app.ui.badge.SetText(text);
    app.ui.badge.Show();
    app.ui.input.SetText("");
    app.ui.input.SetPlaceholderText(placeholder_prefix);
    view.applyFilter(app, "");
}

/// Enters URL mode (auto-detected from typed text). Shows a generic
/// "Browser" badge; the launched command lives in `modes/url.zig`.
pub fn enterUrlMode(app: *state.AppState) void {
    app.mode = .url;
    app.ui.badge.SetText(browser_icon ++ " " ++ browser_name);
    app.ui.badge.Show();
    app.ui.input.SetPlaceholderText(placeholder_url);
}
