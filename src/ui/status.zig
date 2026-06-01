// Status panel: the "no results / waiting for input" label and the badge
// that appears in prefix/url/prompt modes. Single source of truth for what
// the user sees in the status row — call after any state change that
// affects it.

const std = @import("std");
const state = @import("../state/mod.zig");

/// Sets the no_results label text and visibility based on current app
/// state. Idempotent: safe to call after every state change.
pub fn updateNoResults(app: *state.AppState) void {
    // Modes without a list widget never show this label.
    if (!app.mode.hasListSource()) {
        app.ui.no_results.Hide();
        return;
    }

    if (app.visible_indices.items.len > 0) {
        app.ui.no_results.Hide();
        return;
    }

    const text: []const u8 = switch (app.mode) {
        .apps => "No apps found",
        .piped => pipedEmptyText(app),
        .prefix, .url, .prompt => unreachable, // filtered above by hasListSource
    };
    app.ui.no_results.SetText(text);
    app.ui.no_results.Show();
}

fn pipedEmptyText(app: *const state.AppState) []const u8 {
    if (!app.stdin_eof) return "Waiting for input...";
    if (app.piped_items.items.len == 0) return "No input";
    return "No results";
}
