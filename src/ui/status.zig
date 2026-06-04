// Status panel: the "no results / waiting for input" label. Single
// source of truth for what the user sees in the status row — call
// after any state change that affects it. The text and visibility are
// driven by the active mode's `has_list_source` and `emptyText` fields.

const state = @import("../state/mod.zig");

/// Sets the no_results label text and visibility based on current app
/// state. Idempotent: safe to call after every state change.
pub fn updateNoResults(app: *state.AppState) void {
    if (!app.mode.plugin.has_list_source) {
        app.ui.no_results.Hide();
        return;
    }

    if (app.visible_indices.items.len > 0) {
        app.ui.no_results.Hide();
        return;
    }

    const callback = app.mode.plugin.emptyText orelse {
        app.ui.no_results.SetText("No results");
        app.ui.no_results.Show();
        return;
    };
    app.ui.no_results.SetText(callback(app, app.mode.ctx));
    app.ui.no_results.Show();
}
