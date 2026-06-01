// Focus guard callbacks. While the launcher is visible, keep asking Qt to
// keep the top-level window active and keyboard focus on the input.

const qt6 = @import("libqt6zig");
const state = @import("../../state/mod.zig");

const fr = qt6.qnamespace_enums.FocusReason;

pub fn onInputFocusOut(self: qt6.QLineEdit, event: qt6.QFocusEvent) callconv(.c) void {
    self.SuperFocusOutEvent(event);
    keepFocused();
}

pub fn onFocusGuardTimeout(_: qt6.QTimer) callconv(.c) void {
    keepFocused();
}

fn keepFocused() void {
    const app = state.global.get();
    if (!app.ui.main.IsVisible()) return;

    app.ui.main.Raise();
    app.ui.main.ActivateWindow();
    app.ui.input.SetFocus2(fr.ActiveWindowFocusReason);
}
