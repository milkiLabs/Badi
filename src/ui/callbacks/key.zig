// Key-press callback. Maps the four-arrow-keys + Enter + Escape + Ctrl-W
// + Backspace set onto the active mode. Mode-aware Backspace/Ctrl-W
// exits to apps when the input is empty and the active mode opts in
// (`canExitToDefault`). Escape's exit-code-1 path is opt-in per mode
// via `isCancelable`.

const qt6 = @import("libqt6zig");
const state = @import("../../state/mod.zig");
const modes = @import("../../modes/mod.zig");
const view = @import("../view.zig");
const helpers = @import("helpers.zig");

const qk = qt6.qnamespace_enums.Key;
const km = qt6.qnamespace_enums.KeyboardModifier;

pub fn onKeyPress(self: qt6.QLineEdit, event: qt6.QKeyEvent) callconv(.c) void {
    const app = state.global.assertGet();
    const key = event.Key();
    const ctrl = (event.Modifiers() & km.ControlModifier) != 0;

    if (key == qk.Key_Escape) {
        if (app.canExitToDefault()) {
            helpers.exitToApps(app);
        } else if (app.isCancelable()) {
            // Escape cancels the prompt/piped/emoji(--cli) modes — exit
            // code 1 signals "no answer".
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
    } else if (ctrl and key == qk.Key_W) {
        if (tryExitOnEmpty(self, app)) {
            event.Accept();
            return;
        }
        self.CursorWordBackward(true);
        self.Del();
        event.Accept();
    } else if (key == qk.Key_Backspace) {
        if (tryExitOnEmpty(self, app)) {
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

/// Shared by Ctrl+W and Backspace: if the input is empty, exit to apps
/// (when the mode allows it) and report the event as handled. The caller
/// still has to `event.Accept()` in both branches — this only reports
/// whether the key was consumed.
fn tryExitOnEmpty(self: qt6.QLineEdit, app: *state.AppState) bool {
    if (!inputIsEmpty(self, app)) return false;
    if (app.canExitToDefault()) helpers.exitToApps(app);
    return true;
}
