// Key-press callback. Maps the four-arrow-keys + Enter + Escape + Ctrl-W
// + Backspace set onto the active mode. Mode-aware Backspace/Ctrl-W
// exits prefix/url mode when the input is empty.

const std = @import("std");
const qt6 = @import("libqt6zig");
const state = @import("../../state/mod.zig");
const modes = @import("../../modes/mod.zig");
const view = @import("../view.zig");
const helpers = @import("helpers.zig");

const qk = qt6.qnamespace_enums.Key;
const km = qt6.qnamespace_enums.KeyboardModifier;

pub fn onKeyPress(self: qt6.QLineEdit, event: qt6.QKeyEvent) callconv(.c) void {
    const app = state.global.get();
    const key = event.Key();
    const ctrl = (event.Modifiers() & km.ControlModifier) != 0;

    if (key == qk.Key_Escape) {
        if (app.mode == .prefix or app.mode == .url) {
            helpers.exitToApps(app);
        } else if (app.mode == .prompt) {
            // Escape cancels the prompt — exit code 1 signals "no answer".
            app.exit_code = 1;
            _ = app.ui.main.Close();
        } else {
            _ = app.ui.main.Close();
        }
        event.Accept();
    } else if (key == qk.Key_Return or key == qk.Key_Enter) {
        modes.dispatch(app);
        event.Accept();
    } else if (key == qk.Key_Up) {
        view.selectRelative(app, -1);
        event.Accept();
    } else if (key == qk.Key_Down) {
        view.selectRelative(app, 1);
        event.Accept();
    } else if (ctrl and key == qk.Key_C) {
        self.Clear();
        event.Accept();
    } else if (ctrl and key == qk.Key_W) {
        if (inputIsEmpty(self, app)) {
            if (app.mode == .prefix or app.mode == .url) helpers.exitToApps(app);
            event.Accept();
            return;
        }
        self.CursorWordBackward(true);
        self.Del();
        event.Accept();
    } else if (key == qk.Key_Backspace) {
        if (inputIsEmpty(self, app)) {
            if (app.mode == .prefix or app.mode == .url) helpers.exitToApps(app);
            event.Accept();
            return;
        }
        self.SuperKeyPressEvent(event);
    } else {
        self.SuperKeyPressEvent(event);
    }
}

/// Returns true and frees the temporary buffer if the input field is empty.
fn inputIsEmpty(self: qt6.QLineEdit, app: *state.AppState) bool {
    const text = self.Text(app.allocator);
    defer app.allocator.free(text);
    return text.len == 0;
}
