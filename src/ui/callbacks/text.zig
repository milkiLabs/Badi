// Text-changed callback. Delegates per-mode logic to the active
// plugin's `onTextChanged` handler. The default behavior (no handler)
// is "re-filter in the current mode". The apps and url plugins supply
// handlers: apps handles the ": " emoji trigger + prefix triggers +
// URL auto-detect; url handles "backspaced out of URL" revert.

const std = @import("std");
const qt6 = @import("libqt6zig");
const state = @import("../../state/mod.zig");
const view = @import("../view.zig");

pub fn onTextChanged(_: qt6.QLineEdit, text: [*:0]const u8) callconv(.c) void {
    const app = state.global.assertGet();
    const query: []const u8 = std.mem.span(text);

    // Re-entrancy guard: a `setInputText` call from a mode-transition
    // helper fires this signal synchronously. The helper has already
    // switched mode and re-filtered — the handler has nothing to do.
    if (app.setting_text) return;

    if (app.mode.plugin.onTextChanged) |handler| {
        const result = handler(app, app.mode.ctx, query);
        if (result == .continue_filter) view.applyFilter(app, query);
        return;
    }

    // Default: re-filter in the current mode.
    view.applyFilter(app, query);
}
