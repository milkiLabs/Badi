// Qt model adapter: the two C-ABI callbacks Qt invokes to populate the
// list. This is a thin shim — it reads from `state.global.assertGet()`
// and returns the `QVariant` produced by the active mode's `displayRow`
// handler. All real logic (which row, what text) lives in
// `plugins/builtin.zig` and the per-mode files.

const qt6 = @import("libqt6zig");
const state = @import("../state/mod.zig");

const display_role = qt6.qnamespace_enums.ItemDataRole.DisplayRole;

/// Returns the number of rows the model currently has. Called by Qt on
/// every layout pass — keep this cheap.
pub fn onModelRowCount(_: qt6.QAbstractListModel, parent: qt6.QModelIndex) callconv(.c) i32 {
    if (parent.IsValid()) return 0;

    const app = state.global.assertGet();
    return @intCast(app.mode.plugin.resultCount(app, app.mode.ctx));
}

/// Returns the cell data for a (row, role) query. Returns an empty
/// QVariant for anything we don't have data for.
pub fn onModelData(_: qt6.QAbstractListModel, index: qt6.QModelIndex, role: i32) callconv(.c) qt6.QVariant {
    if (role != display_role or !index.IsValid()) return qt6.QVariant.New();

    const row = index.Row();
    if (row < 0) return qt6.QVariant.New();

    const app = state.global.assertGet();
    return app.mode.plugin.displayRow(app, app.mode.ctx, row);
}
