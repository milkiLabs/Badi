// Text-changed callback. Detects mode transitions: prefix triggers, URL
// auto-detection, the ": " emoji trigger, and the reverse (backspacing
// out of a URL or emoji reverts to apps). All other keystrokes just
// re-filter the current view.

const std = @import("std");
const qt6 = @import("libqt6zig");
const state = @import("../../state/mod.zig");
const config = @import("../../config/mod.zig");
const url = @import("../../utils/url.zig");
const view = @import("../view.zig");
const helpers = @import("helpers.zig");

const emoji_trigger = ": ";

pub fn onTextChanged(_: qt6.QLineEdit, text: [*:0]const u8) callconv(.c) void {
    const app = state.global.get();
    const query: []const u8 = std.mem.span(text);

    // Prompt mode: input is the answer, not a launcher query. Just record.
    if (app.mode == .prompt) {
        app.current_query.clearRetainingCapacity();
        app.current_query.appendSlice(app.allocator, query) catch {};
        return;
    }

    // URL mode: if the user backspaced out of a URL, revert to apps.
    if (app.mode == .url) {
        if (!url.isUrl(query)) helpers.exitToApps(app);
        view.applyFilter(app, query);
        return;
    }

    // Apps mode: check for the hardcoded ": " emoji trigger first (cheap,
    // no allocation), then the configured prefix triggers, then URL
    // auto-detect.
    if (app.mode == .apps) {
        if (std.mem.eql(u8, query, emoji_trigger)) {
            helpers.enterEmojiMode(app);
            return;
        }
        for (app.prefixes.items) |cfg| {
            if (matchesTrigger(query, cfg)) {
                helpers.enterPrefixMode(app, cfg);
                return;
            }
        }
        if (url.isUrl(query)) {
            helpers.enterUrlMode(app);
            view.applyFilter(app, query);
            return;
        }
    }

    // Otherwise: re-filter in the current mode (apps/piped/emoji/prefix).
    view.applyFilter(app, query);
}

fn matchesTrigger(query: []const u8, cfg: config.Action) bool {
    return query.len >= cfg.trigger.len and
        std.mem.eql(u8, query[0..cfg.trigger.len], cfg.trigger);
}
