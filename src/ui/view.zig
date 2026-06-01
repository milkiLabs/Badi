// View layer: filter the source, drive selection, scroll. Wraps the pure
// `core.filter` step with the Qt model-reset boilerplate. Anything that
// says "what rows is the user looking at right now?" goes here.

const std = @import("std");
const qt6 = @import("libqt6zig");
const state = @import("../state/mod.zig");
const core = @import("../core/mod.zig");
const status = @import("status.zig");

const display_role = qt6.qnamespace_enums.ItemDataRole.DisplayRole;

/// Recompute visible rows for the current mode and query, reset the Qt
/// model, update the no-results label, and select the first row if any.
pub fn applyFilter(app: *state.AppState, query: []const u8) void {
    // Prompt mode: no list, no filter. Caller may still want to record
    // the query elsewhere; this is a no-op.
    if (app.mode == .prompt) return;

    app.current_query.clearRetainingCapacity();
    app.current_query.appendSlice(app.allocator, query) catch {};
    app.visible_indices.clearRetainingCapacity();
    app.selected_index = null;

    fillVisibleIndices(app, query);

    const has_results = computeHasResults(app, query);
    if (has_results) app.selected_index = 0;

    app.ui.model.BeginResetModel();
    app.ui.model.EndResetModel();

    status.updateNoResults(app);
    if (has_results) selectModelRow(app, 0);
}

fn fillVisibleIndices(app: *state.AppState, query: []const u8) void {
    switch (app.mode) {
        .apps => {
            const source = app.apps();
            var buf: [core.search.max_results]usize = undefined;
            const n = core.filter.filter(
                core.desktop.DesktopEntry,
                core.desktop.nameOf,
                source,
                query,
                &buf,
            );
            appendAll(app, buf[0..n]);
        },
        .piped => {
            const source = app.piped_items.items;
            var buf: [core.search.max_results]usize = undefined;
            const n = core.filter.filter(
                []const u8,
                identityStr,
                source,
                query,
                &buf,
            );
            appendAll(app, buf[0..n]);
        },
        .emoji => {
            const source = app.emojiEntries();
            var buf: [core.search.max_results]usize = undefined;
            const n = core.filter.filter(
                core.emoji.EmojiEntry,
                core.emoji.searchableOf,
                source,
                query,
                &buf,
            );
            appendAll(app, buf[0..n]);
        },
        .prefix, .url, .prompt => {}, // synthetic single row in model.zig, or no list
    }
}

fn identityStr(s: []const u8) []const u8 {
    return s;
}

fn appendAll(app: *state.AppState, indices: []const usize) void {
    for (indices) |idx| {
        app.visible_indices.append(app.allocator, idx) catch break;
    }
}

fn computeHasResults(app: *const state.AppState, query: []const u8) bool {
    return switch (app.mode) {
        .prefix, .url => query.len > 0,
        .prompt => false,
        .apps, .piped, .emoji => app.visible_indices.items.len > 0,
    };
}

/// Move selection by `direction` (negative = up). Wraps around.
pub fn selectRelative(app: *state.AppState, direction: i32) void {
    const len = resultCount(app);
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
    if (selected < resultCount(app)) {
        app.selected_index = selected;
    }
}

pub fn selectModelRow(app: *state.AppState, row: usize) void {
    if (row >= resultCount(app)) return;

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

fn resultCount(app: *const state.AppState) usize {
    return switch (app.mode) {
        .prefix, .url => if (app.current_query.items.len > 0) 1 else 0,
        .prompt => 0,
        .apps, .piped, .emoji => app.visible_indices.items.len,
    };
}
