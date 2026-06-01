// Piped-mode list maintenance. The async stdin pipeline (in
// `ui/callbacks/piped.zig`) hands complete lines to `appendPipedItem`,
// which integrates them into the visible-filter ordering without doing a
// full re-filter. `renderPipedAppendBatch` repaints once at the end of a
// batch — the only Qt update the callbacks need to make.

const std = @import("std");
const state = @import("../state/mod.zig");
const core = @import("../core/mod.zig");
const status = @import("status.zig");
const view = @import("view.zig");

/// Append a single line to the piped items list and integrate it into the
/// visible-filter ordering. Caller owns the line — it will be freed by
/// `AppState.deinit` on shutdown.
pub fn appendPipedItem(app: *state.AppState, line: []const u8) !void {
    errdefer app.allocator.free(line);
    try app.piped_items.append(app.allocator, line);
    if (app.mode != .piped) return;

    const query = app.current_query.items;
    const source_index = app.piped_items.items.len - 1;

    if (query.len == 0) {
        // Empty query: append at end (source order).
        try app.visible_indices.append(app.allocator, source_index);
    } else {
        const s = core.search.score(query, line);
        if (s < 0) return; // doesn't match

        // Find insertion point to keep visible_indices sorted by score desc.
        // We have to re-score each existing item because visible_indices only
        // stores indices, not scores. O(N) per append; fine for our scale.
        var insert_pos = app.visible_indices.items.len;
        for (app.visible_indices.items, 0..) |vis_idx, pos| {
            const existing_text = app.piped_items.items[vis_idx];
            const existing_score = core.search.score(query, existing_text);
            if (s > existing_score) {
                insert_pos = pos;
                break;
            }
        }
        try app.visible_indices.insert(app.allocator, insert_pos, source_index);
    }
    if (app.selected_index == null) app.selected_index = 0;
}

/// Repaint the list widget after a batch of `appendPipedItem` calls. Cheap
/// to call when nothing changed (the model reset is a no-op if the row
/// count is the same).
pub fn renderPipedAppendBatch(app: *state.AppState) void {
    if (app.mode != .piped) return;

    app.ui.model.BeginResetModel();
    app.ui.model.EndResetModel();

    status.updateNoResults(app);
    if (app.visible_indices.items.len > 0) view.selectModelRow(app, app.selected_index orelse 0);
}
