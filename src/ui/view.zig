// View layer: filter the source, drive selection, scroll. Wraps the pure
// `core.filter` step with the Qt model-reset boilerplate. Anything that
// says "what rows is the user looking at right now?" goes here.

const std = @import("std");
const qt6 = @import("libqt6zig");
const state = @import("../state/mod.zig");
const core = @import("../core/mod.zig");
const status = @import("status.zig");

/// Recompute visible rows for the current mode and query, reset the Qt
/// model, update the no-results label, and select the first row if any.
pub fn applyFilter(app: *state.AppState, query: []const u8) void {
    // Prompt mode: no list, no filter. Caller may still want to record
    // the query elsewhere; this is a no-op.
    if (app.mode == .prompt) return;

    app.current_query.clearRetainingCapacity();
    app.current_query.appendSlice(app.allocator, query) catch {};
    app.visible_indices.clearRetainingCapacity();
    app.piped_visible_scores.clearRetainingCapacity();
    app.selected_index = null;

    fillVisibleIndices(app, query);

    const has_results = app.resultCount() > 0;
    if (has_results) app.selected_index = 0;

    app.ui.model.BeginResetModel();
    app.ui.model.EndResetModel();

    status.updateNoResults(app);
    if (has_results) selectModelRow(app, 0);
}

fn fillVisibleIndices(app: *state.AppState, query: []const u8) void {
    switch (app.mode) {
        .apps => fillFor(core.desktop.DesktopEntry, core.desktop.nameOf, app.apps(), app, query),
        .piped => fillPiped(app, query),
        .emoji => fillFor(core.emoji.EmojiEntry, core.emoji.searchableOf, app.emojiEntries(), app, query),
        .prefix, .url, .prompt => {}, // synthetic single row in model.zig, or no list
    }
}

fn fillPiped(app: *state.AppState, query: []const u8) void {
    const source = app.piped_items.items;
    if (source.len == 0) return;

    app.visible_indices.ensureTotalCapacity(app.allocator, source.len) catch return;

    if (query.len == 0) {
        for (0..source.len) |i| {
            app.visible_indices.appendAssumeCapacity(i);
        }
        return;
    }

    app.piped_visible_scores.ensureTotalCapacity(app.allocator, source.len) catch return;

    const scratch = app.allocator.alloc(core.search.ScoredItem, source.len) catch return;
    defer app.allocator.free(scratch);

    const n = core.search.searchMapped([]const u8, identityStr, source, query, scratch);
    for (scratch[0..n]) |item| {
        app.visible_indices.appendAssumeCapacity(item.index);
        app.piped_visible_scores.appendAssumeCapacity(item.score);
    }
}

/// Generic helper: writes filtered indices directly into `visible_indices`.
/// Empty query → zero heap allocs (enumerate in place).
/// Non-empty query → one heap alloc (ScoredItem scratch buffer).
fn fillFor(
    comptime T: type,
    comptime getText: fn (T) []const u8,
    source: []const T,
    app: *state.AppState,
    query: []const u8,
) void {
    if (source.len == 0) return;

    // Grow visible_indices once to fit the worst case (all items match).
    app.visible_indices.ensureTotalCapacity(app.allocator, source.len) catch return;

    if (query.len == 0) {
        // Source order, no scoring, zero heap allocations.
        for (0..source.len) |i| {
            app.visible_indices.appendAssumeCapacity(i);
        }
        return;
    }

    // One heap allocation: the scratch buffer for scoring + sorting.
    const scratch = app.allocator.alloc(core.search.ScoredItem, source.len) catch return;
    defer app.allocator.free(scratch);

    // Write directly into visible_indices' backing memory.
    const out = app.visible_indices.allocatedSlice();
    const n = core.filter.filter(T, getText, source, query, out, scratch);
    app.visible_indices.items.len = n;
}

fn identityStr(s: []const u8) []const u8 {
    return s;
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
