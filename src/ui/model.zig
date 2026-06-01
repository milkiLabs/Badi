// Qt model adapter: the two C-ABI callbacks Qt invokes to populate the
// list. This is a thin shim — it reads from `state.global.get()` and
// returns the right `QVariant` for the requested (row, role). All real
// logic (which row, what text) lives in `view.zig` and the per-mode files.

const std = @import("std");
const qt6 = @import("libqt6zig");
const state = @import("../state/mod.zig");

const display_role = qt6.qnamespace_enums.ItemDataRole.DisplayRole;

/// Returns the number of rows the model currently has. Called by Qt on
/// every layout pass — keep this cheap.
pub fn onModelRowCount(_: qt6.QAbstractListModel, parent: qt6.QModelIndex) callconv(.c) i32 {
    if (parent.IsValid()) return 0;

    const app = state.global.get();
    return switch (app.mode) {
        .prefix, .url => if (app.current_query.items.len > 0) 1 else 0,
        .prompt => 0,
        .apps, .piped => @intCast(app.visible_indices.items.len),
    };
}

/// Returns the cell data for a (row, role) query. Returns an empty
/// QVariant for anything we don't have data for.
pub fn onModelData(_: qt6.QAbstractListModel, index: qt6.QModelIndex, role: i32) callconv(.c) qt6.QVariant {
    if (role != display_role or !index.IsValid()) return qt6.QVariant.New();

    const row = index.Row();
    if (row < 0) return qt6.QVariant.New();

    const app = state.global.get();
    return switch (app.mode) {
        .apps => {
            const src = sourceIndexFromRow(app, row) orelse return qt6.QVariant.New();
            return qt6.QVariant.New24(app.apps()[src].name);
        },
        .piped => {
            const src = sourceIndexFromRow(app, row) orelse return qt6.QVariant.New();
            return qt6.QVariant.New24(app.piped_items.items[src]);
        },
        .prefix => |cfg| syntheticRow(app, row, "Run {s}: {s}", .{ cfg.name, app.current_query.items }),
        .url => syntheticRow(app, row, "Open in browser: {s}", .{app.current_query.items}),
        .prompt => qt6.QVariant.New(),
    };
}

fn sourceIndexFromRow(app: *state.AppState, row: i32) ?usize {
    if (row < 0) return null;
    const idx: usize = @intCast(row);
    if (idx >= app.visible_indices.items.len) return null;
    return app.visible_indices.items[idx];
}

fn syntheticRow(app: *state.AppState, row: i32, comptime fmt: []const u8, args: anytype) qt6.QVariant {
    if (row != 0 or app.current_query.items.len == 0) return qt6.QVariant.New();
    const text = std.fmt.allocPrint(app.allocator, fmt, args) catch return qt6.QVariant.New();
    defer app.allocator.free(text);
    return qt6.QVariant.New24(text);
}
