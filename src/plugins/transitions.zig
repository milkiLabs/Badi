// Generic mode-transition helper shared between `plugins/builtin.zig`
// (the apps mode's `onTextChanged` handler) and `ui/callbacks/helpers.zig`
// (the Esc/Backspace/Ctrl-W key handlers). Each caller constructs the
// target `ActiveMode` and passes it to `enterMode` along with the
// per-transition options.
//
// The transitions that need static mode values (`exitToApps` knows the
// apps mode, `enterEmojiModeTrigger` knows the emoji mode, etc.) are
// defined in `plugins/builtin.zig` next to those mode values — there is
// no need for them to live here.

const state = @import("../state/mod.zig");
const api = @import("api.zig");
const view = @import("../ui/view.zig");

const EnterOptions = struct {
    clear_input: bool = false,
    re_filter: bool = false,
};

/// Generic mode transition. The `beforeEnter` hook (if any) is called
/// first and aborts the transition when it returns false. Then
/// `app.mode` is set, the badge is updated, the placeholder is
/// switched, and the requested follow-up (clear input, re-filter) runs.
pub fn enterMode(app: *state.AppState, active: api.ActiveMode, opts: EnterOptions) void {
    if (active.plugin.beforeEnter) |f| {
        if (!f(app, active.ctx)) return;
    }
    app.mode = active;
    if (app.badgeText()) |text| {
        app.ui.badge.SetText(text);
        app.ui.badge.Show();
    } else {
        app.ui.badge.Hide();
    }
    app.ui.input.SetPlaceholderText(active.plugin.placeholder);
    if (opts.clear_input) app.setInputText("");
    if (opts.re_filter) view.applyFilter(app, "");
}

/// True if `query` starts with the given trigger text. Used by the
/// apps mode's `onTextChanged` handler to detect configured prefix
/// triggers.
pub fn matchesTrigger(query: []const u8, trigger: []const u8) bool {
    return query.len >= trigger.len and
        std.mem.eql(u8, query[0..trigger.len], trigger);
}

const std = @import("std");
