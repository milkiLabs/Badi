// Double-click on a list row: sync selected_index, then launch the
// active mode. This is the mouse equivalent of pressing Enter.

const qt6 = @import("libqt6zig");
const state = @import("../../state/mod.zig");
const modes = @import("../../modes/mod.zig");
const view = @import("../view.zig");

pub fn onItemDoubleClicked(_: qt6.QListView, index: qt6.QModelIndex) callconv(.c) void {
    const app = state.global.assertGet();
    view.syncSelectionFromIndex(app, index);
    modes.dispatch(app);
}
