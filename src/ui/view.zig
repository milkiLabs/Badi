// View layer: filter the source, drive selection, scroll. Wraps the pure
// `core.filter` step with the Qt model-reset boilerplate. Anything that
// says "what rows is the user looking at right now?" goes here. The
// per-mode filter logic lives in `plugins/builtin.zig`; this file only
// owns the Qt-facing glue (model reset, selection reset, scroll-to-row).

const std = @import("std");
const qt6 = @import("libqt6zig");
const state = @import("../state/mod.zig");
const status = @import("status.zig");

/// Recompute visible rows for the current mode and query, reset the Qt
/// model, update the no-results label, and select the first row if any.
pub fn applyFilter(app: *state.AppState, query: []const u8) void {
    // Prompt mode: no list, no filter. Caller may still want to record
    // the query elsewhere; this is a no-op.
    if (std.mem.eql(u8, app.mode.plugin.id, "prompt")) return;

    app.current_query.clearRetainingCapacity();
    app.current_query.appendSlice(app.allocator, query) catch {};
    app.visible_indices.clearRetainingCapacity();
    app.piped_visible_scores.clearRetainingCapacity();
    app.selected_index = null;

    if (app.mode.plugin.has_list_source) {
        app.mode.plugin.filter(app, app.mode.ctx, query);
    }

    const has_results = app.resultCount() > 0;
    if (has_results) app.selected_index = 0;

    app.ui.model.BeginResetModel();
    app.ui.model.EndResetModel();

    status.updateNoResults(app);
    if (has_results) selectModelRow(app, 0);
}

/// Move selection by `direction` (negative = up). Wraps around.
pub fn selectRelative(app: *state.AppState, direction: i32) void {
    const len = app.resultCount();
    if (len == 0) return;

    const current = currentModelRow(app) orelse 0;
    const next: usize = if (direction < 0)
        (if (current == 0) len - 1 else current - 1)
    else if (current + 1 >= len)
        0
    else
        current + 1;

    selectModelRow(app, next);
    app.selected_index = next;
}

/// Set selected_index from a clicked model row (no-op for out-of-range).
pub fn syncSelectionFromIndex(app: *state.AppState, index: qt6.QModelIndex) void {
    if (!index.IsValid()) return;
    const row = index.Row();
    if (row < 0) return;
    const selected: usize = @intCast(row);
    if (selected < app.resultCount()) {
        app.selected_index = selected;
    }
}

pub fn selectModelRow(app: *state.AppState, row: usize) void {
    if (row >= app.resultCount()) return;

    const parent = qt6.QModelIndex.New3();
    defer parent.Delete();
    const index = app.ui.model.Index(@intCast(row), 0, parent);
    defer index.Delete();

    app.ui.list.SetCurrentIndex(index);
    app.ui.list.ScrollTo(index, qt6.qabstractitemview_enums.ScrollHint.EnsureVisible);
}

fn currentModelRow(app: *state.AppState) ?usize {
    const index = app.ui.list.CurrentIndex();
    defer index.Delete();

    if (!index.IsValid()) return app.selected_index;
    const row = index.Row();
    if (row < 0) return app.selected_index;
    return @intCast(row);
}
